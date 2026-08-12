package com.arflix.tv.data.repository.simkl

import com.arflix.tv.data.api.SimklApi
import com.arflix.tv.data.api.SimklPinPollResponse
import com.arflix.tv.data.api.SimklPinResponse
import com.arflix.tv.data.repository.sync.SyncProviderStore
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SimklIntegrationTest {

    private lateinit var simklApi: SimklApi
    private lateinit var syncProviderStore: SyncProviderStore
    private lateinit var authManager: SimklAuthManager
    private lateinit var scrobbler: SimklScrobbler
    private lateinit var syncService: SimklSyncService

    @Before
    fun setUp() {
        simklApi = mockk(relaxed = true)
        syncProviderStore = mockk(relaxed = true)
        authManager = SimklAuthManager(simklApi, syncProviderStore)
        scrobbler = SimklScrobbler(simklApi, authManager)
        syncService = SimklSyncService(simklApi, authManager)
    }

    @Test
    fun testStartPinAuthReturnsResponse() = runBlocking {
        val expected = SimklPinResponse(
            userCode = "SIMKL-123",
            verificationUrl = "https://simkl.com/pin",
            expiresIn = 600
        )
        coEvery { simklApi.getPinCode(any()) } returns expected

        val result = authManager.startPinAuth()
        assertEquals("SIMKL-123", result.userCode)
        assertEquals("https://simkl.com/pin", result.verificationUrl)
    }

    @Test
    fun testPollPinAuthSuccessStoresToken() = runBlocking {
        val pollRes = SimklPinPollResponse(
            result = "OK",
            accessToken = "token_abc123"
        )
        coEvery { simklApi.pollPinToken(any(), any()) } returns pollRes

        val success = authManager.pollPinAuth("SIMKL-123")
        assertTrue(success)
        coVerify { syncProviderStore.setSimklAccessToken("token_abc123") }
    }

    @Test
    fun testDisconnectClearsToken() = runBlocking {
        authManager.disconnect()
        coEvery { syncProviderStore.getSimklAccessToken() } returns null
        assertFalse(authManager.isConnected())
        coVerify { syncProviderStore.setSimklAccessToken(null) }
    }

    @Test
    fun testAddToWatchlistCallsAddToList() = runBlocking {
        coEvery { syncProviderStore.getSimklAccessToken() } returns "token_123"
        coEvery { simklApi.addToList(any(), any(), any()) } returns retrofit2.Response.success(
            mockk<okhttp3.ResponseBody>()
        )

        val success = syncService.addToWatchlist(com.arflix.tv.data.model.MediaType.MOVIE, 12345)
        assertTrue(success)
        coVerify { simklApi.addToList("Bearer token_123", any(), any()) }
    }

    @Test
    fun testRemoveFromWatchlistCallsRemoveFromHistory() = runBlocking {
        coEvery { syncProviderStore.getSimklAccessToken() } returns "token_123"
        coEvery { simklApi.removeFromHistory(any(), any(), any()) } returns retrofit2.Response.success(
            mockk<okhttp3.ResponseBody>()
        )

        val success = syncService.removeFromWatchlist(com.arflix.tv.data.model.MediaType.MOVIE, 12345)
        assertTrue(success)
        coVerify { simklApi.removeFromHistory("Bearer token_123", any(), any()) }
    }

    @Test
    fun testMarkUnwatchedCallsRemoveFromHistory() = runBlocking {
        coEvery { syncProviderStore.getSimklAccessToken() } returns "token_123"
        coEvery { simklApi.removeFromHistory(any(), any(), any()) } returns retrofit2.Response.success(
            mockk<okhttp3.ResponseBody>()
        )

        val success = syncService.markUnwatched(com.arflix.tv.data.model.MediaType.MOVIE, 12345)
        assertTrue(success)
        coVerify { simklApi.removeFromHistory("Bearer token_123", any(), any()) }
    }
}
