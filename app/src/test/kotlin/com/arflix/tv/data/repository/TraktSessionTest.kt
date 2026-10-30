package com.arflix.tv.data.repository

import android.app.Application
import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import com.arflix.tv.data.api.TraktApi
import com.arflix.tv.data.api.TraktToken
import com.arflix.tv.data.api.TraktUserProfile
import com.arflix.tv.util.traktDataStore
import io.mockk.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import retrofit2.HttpException
import retrofit2.Response
import javax.inject.Provider

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
@ConscryptMode(ConscryptMode.Mode.OFF)
class TraktSessionTest {
    private class MemoryStore : DataStore<Preferences> {
        override val data = MutableStateFlow<Preferences>(emptyPreferences())
        private val lock = Mutex()
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences) = lock.withLock {
            transform(data.value).also { data.value = it }
        }
    }
    private val api = mockk<TraktApi>(relaxed = true)
    private val profile = MutableStateFlow("a")
    private val store = MemoryStore()
    private lateinit var session: TraktSession
    private lateinit var profiles: ProfileManager
    private fun token(access: String = "old", refresh: String = "refresh", expires: Int = -1) =
        TraktToken(access, refresh, expires, System.currentTimeMillis() / 1000, "bearer")
    private fun http(code: Int, body: String = "{}") = HttpException(Response.error<Any>(code, body.toResponseBody()))

    @Before fun setup() = runBlocking {
        mockkStatic("com.arflix.tv.util.DataStoresKt")
        every { any<Context>().traktDataStore } returns store
        profiles = mockk<ProfileManager> {
            every { getProfileIdSync() } answers { profile.value }
            every { activeProfileId } returns profile
            every { profileStringKeyFor(any(), any()) } answers { stringPreferencesKey("${firstArg<String>()}_${secondArg<String>()}") }
            every { profileLongKeyFor(any(), any()) } answers { longPreferencesKey("${firstArg<String>()}_${secondArg<String>()}") }
            every { profileBooleanKeyFor(any(), any()) } answers { booleanPreferencesKey("${firstArg<String>()}_${secondArg<String>()}") }
        }
        session = TraktSession(RuntimeEnvironment.getApplication(), profiles, api)
        session.save(token(), "a")
    }

    @After fun cleanup() { unmockkStatic("com.arflix.tv.util.DataStoresKt") }

    @Test fun invalidGrantRequiresReconnectAndUpdatesObservedConnection() = runBlocking {
        coEvery { api.refreshToken(any()) } throws http(400, """{"error":"invalid_grant","error_description":"session not found"}""")
        assertNull(session.accessToken())
        assertEquals(TraktConnection("a", false, true), session.connection.first())
        assertNull(session.accessToken())
        coVerify(exactly = 1) { api.refreshToken(any()) }
    }

    @Test fun refresh401RequiresReconnect() = runBlocking {
        coEvery { api.refreshToken(any()) } throws http(401)
        assertNull(session.accessToken())
        assertTrue(session.connection.first().reconnectRequired)
    }

    @Test fun transientResponsesPreserveConnectionAndRespectBackoff() = runBlocking {
        for (code in listOf(400, 403, 429, 500, 503)) {
            session.save(token(refresh = "r$code"), "a")
            coEvery { api.refreshToken(any()) } throws http(code)
            assertNull(session.accessToken())
            assertTrue(session.connection.first().connected)
            assertFalse(session.connection.first().reconnectRequired)
            assertNull(session.accessToken())
        }
        coVerify(exactly = 5) { api.refreshToken(any()) }
    }

    @Test fun offlineRefreshKeepsAnUnexpiredAccessToken() = runBlocking {
        session.save(token(expires = 600), "a")
        coEvery { api.refreshToken(any()) } throws java.io.IOException("offline")
        assertEquals("old", session.accessToken())
        assertTrue(session.connection.first().connected)
    }

    @Test fun simultaneousForegroundAndBackgroundRequestsRotateOnlyOnce() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        coEvery { api.refreshToken(any()) } coAnswers {
            entered.complete(Unit)
            finish.await()
            token("new", "rotated", 86_400)
        }
        val first = async { session.accessToken() }
        entered.await()
        val second = async(start = CoroutineStart.UNDISPATCHED) { session.accessToken() }
        finish.complete(Unit)
        assertEquals(listOf("new", "new"), awaitAll(first, second))
        coVerify(exactly = 1) { api.refreshToken(any()) }
    }

    @Test fun repositoryAndSyncServiceUseTheSameRotatingSession() = runBlocking {
        val context: Context = RuntimeEnvironment.getApplication()
        val auth = mockk<AuthRepository>(relaxed = true) {
            every { getCurrentUserId() } returns null
        }
        val service = TraktSyncService(context, api, mockk(relaxed = true), auth,
            mockk(relaxed = true), profiles, mockk(relaxed = true), mockk(relaxed = true), session)
        val repository = TraktRepository(context, api, mockk(), OkHttpClient(), Provider { service },
            profiles, mockk(relaxed = true), mockk(relaxed = true), mockk(relaxed = true),
            mockk(relaxed = true), ContinueWatchingUpdates(), traktSession = session)
        val entered = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        coEvery { api.refreshToken(any()) } coAnswers {
            entered.complete(Unit)
            finish.await()
            token("new", "rotated", 86_400)
        }
        val foreground = async { repository.refreshTokenIfNeeded() }
        entered.await()
        val background = async { service.performFullSync() }
        finish.complete(Unit)
        assertEquals("new", foreground.await())
        assertEquals(SyncResult.Success(0, 0), background.await())
        coVerify(exactly = 1) { api.refreshToken(any()) }
        coVerify { api.getWatchedMovies("Bearer new", any(), any(), any(), any(), any()) }
    }

    @Test fun api401ForcesRefreshEvenWithFutureExpiry() = runBlocking {
        session.save(token(expires = 86_400), "a")
        coEvery { api.refreshToken(any()) } returns token("new", "rotated", 86_400)
        val headers = mutableListOf<String>()
        val result = session.authorized { header ->
            headers += header
            if (header == "Bearer old") throw http(401)
            "ok"
        }
        assertEquals("ok", result)
        assertEquals(listOf("Bearer old", "Bearer new"), headers)
        coVerify(exactly = 1) { api.refreshToken(any()) }
    }

    @Test fun credentialsPersistAcrossAnAppRestartOrUpdate() = runBlocking {
        val restarted = TraktSession(RuntimeEnvironment.getApplication(), profiles, api)
        coEvery { api.refreshToken(any()) } returns token("renewed", "rotated", 86_400)
        assertEquals("renewed", restarted.accessToken())
        assertTrue(restarted.connection.first().connected)
        coVerify(exactly = 1) { api.refreshToken(match { it.refreshToken == "refresh" }) }
    }

    @Test fun settingsUsernameCheckRecoversARejectedAccessToken() = runBlocking {
        session.save(token(expires = 86_400), "a")
        coEvery { api.getMe("Bearer old", any(), any()) } throws http(401)
        coEvery { api.getMe("Bearer new", any(), any()) } returns TraktUserProfile("tester")
        coEvery { api.refreshToken(any()) } returns token("new", "rotated", 86_400)
        val repository = TraktRepository(RuntimeEnvironment.getApplication(), api, mockk(), OkHttpClient(),
            Provider { mockk(relaxed = true) }, profiles, mockk(relaxed = true), mockk(relaxed = true),
            mockk(relaxed = true), mockk(relaxed = true), ContinueWatchingUpdates(), traktSession = session)
        assertEquals("tester", repository.fetchUsername())
        assertEquals(TraktConnection("a", true, false), repository.connection.first())
    }

    @Test fun late401UsesAlreadyRotatedTokenInsteadOfRefreshingAgain() = runBlocking {
        session.save(token("new", "rotated", 86_400), "a")
        assertEquals("new", session.accessToken(force = true, rejectedAccessToken = "old"))
        coVerify(exactly = 0) { api.refreshToken(any()) }
    }

    @Test fun staleRefreshFailureCannotDisconnectANewLogin() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        coEvery { api.refreshToken(any()) } coAnswers {
            entered.complete(Unit)
            finish.await()
            throw http(400, """{"error":"invalid_grant"}""")
        }
        val pending = async { session.accessToken() }
        entered.await()
        session.save(token("login", "login-refresh", 86_400), "a")
        finish.complete(Unit)
        assertEquals("login", pending.await())
        assertEquals(TraktConnection("a", true, false), session.connection.first())
    }

    @Test fun staleRefreshSuccessCannotUndoLogout() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        coEvery { api.refreshToken(any()) } coAnswers {
            entered.complete(Unit)
            finish.await()
            token("new", "rotated", 86_400)
        }
        val pending = async { session.accessToken() }
        entered.await()
        session.disconnect()
        finish.complete(Unit)
        assertNull(pending.await())
        assertEquals(TraktConnection("a", false, false), session.connection.first())
    }

    @Test fun refreshResponseIsSavedToOriginalProfileAfterSwitch() = runBlocking {
        coEvery { api.refreshToken(any()) } coAnswers {
            profile.value = "b"
            token("new-a", "rotated", 86_400)
        }
        session.save(token("b", "b-refresh", 86_400), "b")
        assertEquals("new-a", session.accessToken())
        assertEquals("b", session.accessToken())
        assertEquals("new-a", session.accessToken("a"))
    }

    @Test fun revokedSessionOnlyChangesItsOwnProfile() = runBlocking {
        session.save(token("b", "b-refresh", 86_400), "b")
        coEvery { api.refreshToken(any()) } coAnswers {
            profile.value = "b"
            throw http(400, """{"error":"invalid_grant"}""")
        }
        assertNull(session.accessToken())
        assertEquals(TraktConnection("b", true, false), session.connection.first())
        assertEquals("b", session.accessToken())
    }

    @Test fun aSecondApi401RequiresReconnect() = runBlocking {
        coEvery { api.refreshToken(any()) } returns token("new", "rotated", 86_400)
        try {
            session.authorized<Unit> { throw http(401) }
            fail("Expected reconnect error")
        } catch (error: TraktAuthUnavailable) {
            assertTrue(error.reconnectRequired)
        }
        assertFalse(session.connection.first().connected)
    }

    @Test fun cancellationIsNotTurnedIntoBackoffOrLogout() = runBlocking {
        coEvery { api.refreshToken(any()) } throws CancellationException("cancelled")
        try {
            session.accessToken()
            fail("Expected cancellation")
        } catch (_: CancellationException) { }
        coEvery { api.refreshToken(any()) } returns token("new", "rotated", 86_400)
        assertEquals("new", session.accessToken())
    }

    @Test fun reconnectAndExplicitDisconnectClearTheReconnectWarning() = runBlocking {
        coEvery { api.refreshToken(any()) } throws http(400, """{"error":"invalid_grant"}""")
        session.accessToken()
        session.save(token("login", "login-refresh", 86_400), "a")
        assertFalse(session.connection.first().reconnectRequired)
        session.disconnect()
        assertEquals(TraktConnection("a", false, false), session.connection.first())
    }
}
