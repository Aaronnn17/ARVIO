package com.arflix.tv.ui.screens.player.preview

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/** One small copy of an already-rendered video frame; no decoder, network or playback seek. */
internal suspend fun captureRenderedSeekPreview(surface: Surface, width: Int, height: Int): Bitmap? =
    suspendCancellableCoroutine { continuation ->
        val bitmap = try { Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888) }
        catch (_: OutOfMemoryError) { continuation.resume(null); return@suspendCancellableCoroutine }
        try {
            PixelCopy.request(surface, bitmap, { result ->
                if (result == PixelCopy.SUCCESS && continuation.isActive) {
                    continuation.resume(bitmap, onCancellation = { _, value, _ -> value?.recycle() })
                } else {
                    bitmap.recycle()
                    if (continuation.isActive) continuation.resume(null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (_: IllegalArgumentException) {
            bitmap.recycle()
            if (continuation.isActive) continuation.resume(null)
        }
    }
