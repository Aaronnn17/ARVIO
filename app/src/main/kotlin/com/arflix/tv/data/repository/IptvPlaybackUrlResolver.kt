package com.arflix.tv.data.repository

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.net.URI
import java.util.Locale
import com.arflix.tv.network.iptvProviderCooldownMs

internal fun buildXtreamLiveStreamUrl(
    baseUrl: String,
    username: String,
    password: String,
    streamId: Int,
    containerExtension: String?,
): String {
    val normalized = containerExtension?.trim()?.lowercase(Locale.ROOT)
    val extension = when (normalized) {
        "m3u8", "ts", "mp4", "mpd" -> normalized
        else -> "ts"
    }
    return baseUrl.trimEnd('/').toHttpUrl().newBuilder()
        .addPathSegment("live").addPathSegment(username).addPathSegment(password)
        .addPathSegment("$streamId.$extension").build().toString()
}

internal data class IptvPlaybackTarget(
    val url: String,
    val isHls: Boolean = false,
    /**
     * Container MIME type the server stated in its `Content-Type`, when it is one the
     * player cannot reliably infer from the URL. Null means "let the player sniff".
     */
    val mimeType: String? = null,
)

internal class IptvPlaybackUrlResolver(
    private val client: OkHttpClient,
    private val cacheTtlMs: Long = 5 * 60_000L,
    private val maxCacheEntries: Int = 256,
) {
    private data class ProbeResult(
        val target: IptvPlaybackTarget,
        val isConclusive: Boolean,
        val statusCode: Int,
    )

    private data class CachedTarget(
        val target: IptvPlaybackTarget,
        val resolvedAtMs: Long,
    )

    private val cache = LinkedHashMap<String, CachedTarget>()
    private val failedUntil = LinkedHashMap<String, Long>()

    suspend fun resolve(
        rawUrl: String,
        headers: Map<String, String>,
        forceRefresh: Boolean = false,
        probeKnownUrl: Boolean = false,
    ): IptvPlaybackTarget {
        val url = rawUrl.trim()
        val inferredTarget = IptvPlaybackTarget(
            url = url,
            isHls = looksLikeHlsPlaybackUrl(url),
        )
        val now = System.currentTimeMillis()
        synchronized(cache) {
            if ((failedUntil[url] ?: 0L) > now) return inferredTarget
        }
        if (!forceRefresh) {
            synchronized(cache) {
                cache[url]
                    ?.takeIf { now - it.resolvedAtMs <= cacheTtlMs }
                    ?.let { return it.target }
            }
        }
        // A provider may serve HLS from a .ts URL. Keep a successfully probed
        // format on subsequent selections instead of repeating the parse failure.
        if (!probeKnownUrl && !shouldResolveIptvPlaybackRedirect(url)) return inferredTarget

        val resolved = withContext(Dispatchers.IO) {
            val headProbe = executeProbe(url, headers, useHead = true)
            if (headProbe?.isConclusive == true) {
                headProbe.target
            } else if (headProbe != null && iptvProviderCooldownMs(headProbe.statusCode, null, now) > 0L) {
                null
            } else {
                executeProbe(url, headers, useHead = false)?.takeIf { it.isConclusive }?.target
            }
        }

        if (resolved == null) {
            synchronized(cache) {
                failedUntil[url] = now + 60_000L
                while (failedUntil.size > maxCacheEntries) failedUntil.remove(failedUntil.keys.first())
            }
            return inferredTarget
        }
        synchronized(cache) {
            failedUntil.remove(url)
            cache[url] = CachedTarget(resolved, now)
            while (cache.size > maxCacheEntries) {
                val firstKey = cache.keys.firstOrNull() ?: break
                cache.remove(firstKey)
            }
        }
        return resolved
    }

    private fun executeProbe(
        url: String,
        headers: Map<String, String>,
        useHead: Boolean,
    ): ProbeResult? {
        return try {
            val request = Request.Builder()
                .url(url)
                .apply {
                    if (useHead) {
                        head()
                    } else {
                        get()
                        header("Range", "bytes=0-63")
                    }
                }
                .header("Accept", "*/*")
                .header("Accept-Encoding", "identity")
                .apply {
                    headers.forEach { (name, value) ->
                        if (name.isNotBlank() && value.isNotBlank() && !name.equals("Range", ignoreCase = true)) {
                            header(name, value)
                        }
                    }
                }
                .build()

            client.newCall(request).execute().use { response ->
                val finalUrl = response.request.url.toString().ifBlank { url }
                val contentType = response.header("Content-Type")
                val bodyStartsWithM3u = if (!useHead) {
                    response.peekBody(64).string().trimStart().startsWith("#EXTM3U", ignoreCase = true)
                } else {
                    false
                }
                val target = IptvPlaybackTarget(
                    url = finalUrl,
                    isHls = looksLikeHlsPlaybackUrl(finalUrl) ||
                        contentType.isHlsContentType() ||
                        bodyStartsWithM3u,
                    mimeType = contentType.asTransportStreamMimeType(),
                )
                ProbeResult(
                    target = target,
                    statusCode = response.code,
                    isConclusive = response.isSuccessful && (target.isHls ||
                        contentType.isDirectMediaContentType()),
                )
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: java.io.IOException) {
            null
        } catch (e: java.lang.IllegalArgumentException) {
            null
        } catch (e: Exception) {
            null
        }
    }
}

internal fun shouldResolveIptvPlaybackRedirect(url: String): Boolean {
    val trimmed = url.trim()
    if (trimmed.isBlank()) return false
    if (!trimmed.startsWith("http://", ignoreCase = true) && !trimmed.startsWith("https://", ignoreCase = true)) {
        return false
    }
    if (looksLikeHlsPlaybackUrl(trimmed)) return false

    val uri = try { URI(trimmed) } catch (e: java.net.URISyntaxException) { null } catch (e: java.lang.IllegalArgumentException) { null } ?: return false
    val path = uri.path.orEmpty().trimEnd('/').lowercase(Locale.US)
    val lastSegment = path.substringAfterLast('/')
    if (lastSegment.isBlank() || lastSegment.contains('.')) return false

    // Standard Xtream numeric IDs are direct MPEG-TS streams, so there is nothing a
    // probe could add. Every other extension-less address is opaque — slug providers
    // that redirect to HLS as well as portals that hand out a single-segment token
    // URL. For those the server's own `Content-Type` is the only reliable signal, and
    // guessing where an answer is available is what broke playback on token portals.
    return lastSegment.toLongOrNull() == null
}

internal fun looksLikeHlsPlaybackUrl(url: String): Boolean {
    val lower = url.lowercase(Locale.US)
    val path = lower.substringBefore('?').substringBefore('#')
    return path.endsWith(".m3u8") ||
        path.contains("/hls/") ||
        "output=m3u8" in lower ||
        "format=hls" in lower
}

private fun String?.isHlsContentType(): Boolean {
    val value = this.orEmpty().lowercase(Locale.US)
    return "mpegurl" in value || "vnd.apple.mpegurl" in value
}

/**
 * MPEG-TS is the one container Media3 regularly fails to infer from an extension-less
 * URL, and the one portals actually announce (`Content-Type: video/mp2t`). Other
 * containers are left to the player's own sniffing rather than risking a wrong hint.
 */
private fun String?.asTransportStreamMimeType(): String? {
    val value = this.orEmpty().lowercase(Locale.US).substringBefore(';').trim()
    return when (value) {
        "video/mp2t", "video/mpeg", "video/ts", "application/mp2t", "application/x-mpegts" ->
            "video/mp2t"
        else -> null
    }
}

private fun String?.isDirectMediaContentType(): Boolean {
    val value = this.orEmpty().lowercase(Locale.US).substringBefore(';').trim()
    return value.startsWith("video/") ||
        value.startsWith("audio/") ||
        value == "application/octet-stream"
}
