package com.arflix.tv.ui.screens.player.preview

import com.arflix.tv.data.model.IptvVodSourceIds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

// Provider image previews and already captured frames remain available. A second
// video connection may violate the IPTV subscription's single-connection limit.
internal fun allowSecondarySeekPreviewExtraction(memoryClassMb: Int, addonId: String?): Boolean =
    memoryClassMb >= 192 && !IptvVodSourceIds.isIptvVodAddonId(addonId)

/** Output scaling does not reduce the decoder's full-resolution working buffers. */
internal fun seekPreviewDecodeFitsMemory(memoryClassMb: Int, lowRam: Boolean, width: Int, height: Int, mime: String?): Boolean {
    if (lowRam || width <= 0 || height <= 0 || mime == "video/dolby-vision") return false
    val maxPixels = if (memoryClassMb >= 512) 3840L * 2160L else 1920L * 1080L
    return memoryClassMb >= 192 && width.toLong() * height <= maxPixels
}

/** A cancelled decoder request is a missing frame, not a cancelled UI loading effect. */
internal suspend fun loadSeekPreviewFrame(provider: SeekPreviewFrameProvider, targetMs: Long): SeekPreviewFrame? =
    try {
        withTimeoutOrNull(SEEK_PREVIEW_REQUEST_TIMEOUT_MS + 1_000L) {
            provider.cachedFrameAt(targetMs) ?: provider.frameAt(targetMs)
        }
    } catch (cancelled: CancellationException) {
        currentCoroutineContext().ensureActive()
        null
    }
