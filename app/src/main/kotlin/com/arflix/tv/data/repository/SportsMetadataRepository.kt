package com.arflix.tv.data.repository

import com.arflix.tv.BuildConfig
import com.arflix.tv.data.model.SportsEventArtwork
import com.arflix.tv.data.model.parseSportsMetadata
import com.arflix.tv.util.Constants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SportsMetadataRepository @Inject constructor(client: OkHttpClient) {
    private val http = client.newBuilder().callTimeout(8, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
    private val mutex = Mutex()
    private var cached = emptyList<SportsEventArtwork>()
    private var retryAfter = 0L
    private var lastSuccess = 0L

    suspend fun load(): List<SportsEventArtwork> = withContext(Dispatchers.IO) {
        mutex.withLock {
            val now = android.os.SystemClock.elapsedRealtime()
            if (now < retryAfter) return@withLock cached
            val endpoint = BuildConfig.SPORTS_METADATA_URL.ifBlank {
                "${Constants.NETLIFY_BACKEND_URL.ifBlank { "https://auth.arvio.tv/.netlify/functions" }}/sports-metadata"
            }
            val result = runCatching {
                http.newCall(Request.Builder().url(endpoint).get().build()).execute().use { response ->
                    check(response.isSuccessful)
                    val body = response.body ?: error("Empty sports metadata")
                    check(body.contentLength() <= 6_000_000)
                    parseSportsMetadata(body.string())
                }
            }.getOrNull()
            if (result != null) { cached = result; lastSuccess = now }
            else if (now - lastSuccess > 86_400_000) cached = emptyList()
            retryAfter = now + if (result.isNullOrEmpty()) 60_000 else 10 * 60_000
            cached
        }
    }
}
