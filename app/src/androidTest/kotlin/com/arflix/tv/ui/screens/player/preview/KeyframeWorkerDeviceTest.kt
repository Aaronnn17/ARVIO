package com.arflix.tv.ui.screens.player.preview

import android.graphics.Color
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import fi.iki.elonen.NanoHTTPD
import java.io.ByteArrayInputStream
import java.io.File
import java.net.ServerSocket
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.cancelAndJoin
import okhttp3.OkHttpClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class KeyframeWorkerDeviceTest {
    @Test fun unwatched4kMain10FramesUseIndependentWorkerAndActualTimestamps() = runBlocking<Unit> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val bytes = instrumentation.context.assets.open("seek_preview_4k_main10.mp4").use { it.readBytes() }
        val port = ServerSocket(0).use { it.localPort }
        var authenticatedRanges = 0
        val server = object : NanoHTTPD("127.0.0.1", port) {
            override fun serve(session: IHTTPSession): Response {
                if (session.headers["x-preview-test"] != "native")
                    return newFixedLengthResponse(Response.Status.UNAUTHORIZED, "text/plain", "")
                if (session.method == Method.HEAD) return newFixedLengthResponse(Response.Status.OK, "video/mp4", "").apply {
                    addHeader("Content-Length", bytes.size.toString())
                    addHeader("Accept-Ranges", "bytes")
                }
                val range = session.headers["range"]?.removePrefix("bytes=")
                val start = range?.substringBefore('-')?.toIntOrNull() ?: 0
                val end = (range?.substringAfter('-')?.toIntOrNull() ?: bytes.lastIndex).coerceAtMost(bytes.lastIndex)
                if (start !in bytes.indices || end < start)
                    return newFixedLengthResponse(Response.Status.RANGE_NOT_SATISFIABLE, "text/plain", "")
                if (range != null) authenticatedRanges++
                return newFixedLengthResponse(if (range == null) Response.Status.OK else Response.Status.PARTIAL_CONTENT,
                    "video/mp4", ByteArrayInputStream(bytes, start, end - start + 1), (end - start + 1).toLong()).apply {
                    addHeader("Accept-Ranges", "bytes")
                    if (range != null) addHeader("Content-Range", "bytes $start-$end/${bytes.size}")
                }
            }
        }.apply { start(NanoHTTPD.SOCKET_READ_TIMEOUT, false) }
        val report = JSONObject()
        try {
            SeekPreviewFrameProvider(context, OkHttpClient(), 192).use { provider ->
                provider.configure(SeekPreviewSource("http://127.0.0.1:$port/video.mp4",
                    mapOf("X-Preview-Test" to "native"), "native-4k-${SystemClock.elapsedRealtime()}",
                    24_000, false, false, useNativeKeyframes = true))
                val start = SystemClock.elapsedRealtime()
                val green = provider.frameAt(12_000)
                report.put("coldMs", SystemClock.elapsedRealtime() - start)
                assertNotNull("Unwatched HEVC Main10 4K frame must decode", green)
                assertTrue(provider.matchesTarget(green, 12_000))
                val greenPixel = green!!.bitmap.getPixel(green.bitmap.width / 2, green.bitmap.height / 2)
                assertTrue(Color.green(greenPixel) > Color.red(greenPixel) + 30)
                val next = SystemClock.elapsedRealtime()
                val blue = provider.frameAt(20_000)
                report.put("secondMs", SystemClock.elapsedRealtime() - next)
                assertNotNull(blue)
                assertTrue(provider.matchesTarget(blue, 20_000))
                val bluePixel = blue!!.bitmap.getPixel(blue.bitmap.width / 2, blue.bitmap.height / 2)
                assertTrue(Color.blue(bluePixel) > Color.green(bluePixel) + 30)
                report.put("firstActualMs", green.actualPositionMs).put("secondActualMs", blue.actualPositionMs)
                val cached = SystemClock.elapsedRealtime()
                assertNotNull(provider.memoryFrameAt(20_000))
                report.put("cachedMs", SystemClock.elapsedRealtime() - cached)
                assertTrue("Remote headers must be preserved by the bridge", authenticatedRanges > 0)
                val trimOutput = android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("am send-trim-memory ${context.packageName}:seek_preview RUNNING_LOW")
                ).bufferedReader().use { it.readText() }
                assertTrue("Memory pressure must reach the independent worker", trimOutput.isBlank())
                val pending = launch { provider.frameAt(4_000) }
                delay(1)
                pending.cancelAndJoin()
                provider.cancelPending()
                provider.configure(SeekPreviewSource("http://127.0.0.1:$port/video.mp4",
                    mapOf("X-Preview-Test" to "native"), "replacement-${SystemClock.elapsedRealtime()}",
                    24_000, false, false, useNativeKeyframes = true))
                assertNull("A previous source's cached frames must not leak", provider.memoryFrameAt(20_000))
                val red = provider.frameAt(4_000)
                assertNotNull("Cancellation/source replacement must not poison the worker", red)
                assertTrue(provider.matchesTarget(red, 4_000))
                val redPixel = red!!.bitmap.getPixel(red.bitmap.width / 2, red.bitmap.height / 2)
                assertTrue(Color.red(redPixel) > Color.blue(redPixel) + 30)
                report.put("cancellationAndSourceReplacement", true)
                report.put("memoryPressureRecovery", true)
            }
        } finally {
            server.stop()
            File(context.getExternalFilesDir(null), "native-keyframe-report.json").writeText(report.toString(2))
        }
    }
}
