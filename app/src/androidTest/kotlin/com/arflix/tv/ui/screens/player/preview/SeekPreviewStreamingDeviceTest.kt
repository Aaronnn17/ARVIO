package com.arflix.tv.ui.screens.player.preview

import android.graphics.Bitmap
import android.os.SystemClock
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.arflix.tv.MainActivity
import java.io.File
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Call
import okhttp3.EventListener
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in live test. Signed URLs/headers are supplied on-device, never in source or test output. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class SeekPreviewStreamingDeviceTest {
    @Test fun livePreviewDecodesAtRemotePosition() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val input = File(context.getExternalFilesDir(null), "seek-stream-private.json")
        assumeTrue(input.exists())
        val config = JSONObject(input.readText())
        val observations = java.util.Collections.synchronizedList(mutableListOf<JSONObject>())
        val client = OkHttpClient.Builder().eventListenerFactory {
            object : EventListener() {
                var start = 0L
                val item = JSONObject()
                override fun callStart(call: Call) {
                    start = SystemClock.elapsedRealtime()
                    item.put("method", call.request().method).put("range", call.request().header("Range"))
                }
                override fun responseHeadersEnd(call: Call, response: Response) { item.put("status", response.code) }
                override fun responseBodyEnd(call: Call, byteCount: Long) { item.put("bytes", byteCount) }
                override fun callEnd(call: Call) { item.put("ms", SystemClock.elapsedRealtime() - start); observations.add(item) }
                override fun callFailed(call: Call, ioe: java.io.IOException) {
                    item.put("failure", ioe.javaClass.simpleName).put("ms", SystemClock.elapsedRealtime() - start)
                    observations.add(item)
                }
            }
        }.build()
        val report = JSONObject()
        File(context.getExternalFilesDir(null), "seek-cold-report.json").delete()
        SeekPreviewFrameProvider(context, client, 256).use { provider ->
            val headers = config.optJSONObject("headers")?.let { o -> o.keys().asSequence().associateWith { o.getString(it) } }.orEmpty()
            provider.configure(SeekPreviewSource(config.getString("url"), headers, "cold-live-${SystemClock.elapsedRealtime()}", 3_000_000, false, false))
            try {
                val start = SystemClock.elapsedRealtime()
                val frame = provider.frameAt(120_000)
                report.put("coldMs", SystemClock.elapsedRealtime() - start).put("available", frame != null)
                if (config.optBoolean("requirePreview", true)) {
                    assertNotNull("Live source must decode a timestamp-validated frame", frame)
                }
                if (frame != null) assertTrue(provider.matchesTarget(frame, 120_000))
                report.put("actualMs", frame?.actualPositionMs).put("completedWithoutCrash", true)
            } finally {
                report.put("requests", JSONArray(observations.toList()))
                File(context.getExternalFilesDir(null), "seek-cold-report.json").writeText(report.toString(2))
            }
        }
    }

    @Test fun liveStreamPlaybackWithAndWithoutPreviewWork() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val input = File(context.getExternalFilesDir(null), "seek-stream-private.json")
        assumeTrue("Supply a private live-stream fixture on the emulator", input.exists())
        val config = JSONObject(input.readText())
        val url = config.getString("url")
        val headers = config.optJSONObject("headers")?.let { o -> o.keys().asSequence().associateWith { o.getString(it) } }.orEmpty()
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        var player: ExoPlayer? = null
        var videoSurface: android.view.SurfaceView? = null
        val renderedPts = java.util.concurrent.atomic.AtomicLong(-1L)
        var errors = 0
        var rebuffers = 0
        var dropped = 0
        var measuring = false
        val selected = mutableStateOf<SeekPreviewFrame?>(null)
        val neighbors = mutableStateOf<List<SeekPreviewFrame>>(emptyList())
        val selectedPosition = mutableStateOf(120_000L)
        val provider = SeekPreviewFrameProvider(context, OkHttpClient(), 256)
        val report = JSONObject()
        File(context.getExternalFilesDir(null), "seek-stream-report.json").delete()
        suspend fun <T> main(block: () -> T): T = withContext(Dispatchers.Main) { block() }
        try {
            scenario.onActivity { activity ->
                val http = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
                player = ExoPlayer.Builder(activity).setMediaSourceFactory(DefaultMediaSourceFactory(http)).build().also { p ->
                    p.setVideoFrameMetadataListener { pts, _, _, _ -> renderedPts.set(pts / 1_000L) }
                    p.addListener(object : Player.Listener {
                        override fun onPlayerError(error: PlaybackException) { errors++ }
                        override fun onPlaybackStateChanged(state: Int) {
                            if (measuring && state == Player.STATE_BUFFERING) rebuffers++
                        }
                    })
                    p.addAnalyticsListener(object : AnalyticsListener {
                        override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
                            dropped += droppedFrames
                        }
                    })
                    p.setMediaItem(MediaItem.fromUri(url))
                    p.prepare()
                    p.play()
                }
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(Color.Black)) {
                        AndroidView(factory = { PlayerView(it).also { view ->
                            view.player = player; view.useController = false
                            videoSurface = view.videoSurfaceView as? android.view.SurfaceView
                        } }, modifier = Modifier.fillMaxSize())
                        if (selected.value != null) SeekPreviewFilmstrip(selected.value, neighbors.value,
                            selectedPosition.value, provider.sourceGeneration,
                            Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 48.dp, vertical = 40.dp))
                    }
                }
            }
            withTimeout(60_000) { while (!main { player!!.isPlaying && player!!.currentPosition > 2_000 }) delay(250) }
            val duration = main { player!!.duration }
            assertTrue("The live file must have a seekable duration", duration > 180_000)
            provider.configure(SeekPreviewSource(url, headers, "live-test-${SystemClock.elapsedRealtime()}", duration, false, false))
            main { measuring = true }
            val baselineStart = main { player!!.currentPosition }
            val dropsStart = main { dropped }
            delay(30_000)
            report.put("baseline", JSONObject().put("positionAdvancedMs", main { player!!.currentPosition } - baselineStart)
                .put("rebuffers", main { rebuffers }).put("droppedFrames", main { dropped } - dropsStart))
            main { rebuffers = 0 }
            val enabledStart = main { player!!.currentPosition }
            val enabledDrops = main { dropped }
            val guard = SeekPreviewPlaybackGuard()
            var job: Job? = null
            var turns = 0
            var captured = 0
            var lastBucket = -1L
            val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val isTv = context.packageManager.hasSystemFeature("android.software.leanback")
            val resourceSafe = !activityManager.isLowRamDevice && activityManager.memoryClass >= 256 &&
                !(isTv && activityManager.memoryClass <= 384)
            report.put("memoryClassMb", activityManager.memoryClass).put("backgroundDecodeAllowed", resourceSafe)
            var nextAt = 0L
            val end = SystemClock.elapsedRealtime() + 45_000
            try {
                while (SystemClock.elapsedRealtime() < end) {
                    val now = SystemClock.elapsedRealtime()
                    val safe = main { guard.mayWarm(now, player!!.isPlaying,
                        player!!.playbackState == Player.STATE_READY, player!!.totalBufferedDuration,
                        false, true, resourceSafe) }
                    // Exercise the same no-extra-decoder path used on constrained devices.
                    main {
                        val p = player!!
                        val pts = renderedPts.get()
                        val bucket = quantizeSeekPreviewPosition(p.currentPosition, duration)
                        val surface = videoSurface?.holder?.surface
                        if (bucket != lastBucket && kotlin.math.abs(p.currentPosition - bucket) <= 750 &&
                            kotlin.math.abs(pts - p.currentPosition) <= 500 && p.isPlaying && surface?.isValid == true) {
                            lastBucket = bucket
                            val before = pts
                            val generation = provider.sourceGeneration
                            launch(Dispatchers.Main) {
                                val bitmap = withTimeoutOrNull(RENDERED_PREVIEW_COPY_TIMEOUT_MS) { captureRenderedSeekPreview(surface, 320, 180) }
                                if (bitmap != null) {
                                    if (renderedPreviewCopyIsCurrent(before, renderedPts.get(), p.currentPosition) && p.isPlaying) {
                                        if (provider.rememberRenderedFrame(before, bitmap, generation) != null) captured++
                                        else bitmap.recycle()
                                    } else bitmap.recycle()
                                }
                            }
                        }
                    }
                    if (!safe && job?.isActive == true) { job?.cancel(); provider.cancelPending() }
                    if (safe && job?.isActive != true && now >= nextAt) {
                        val position = main { player!!.currentPosition }
                        nextAt = now + 8_000
                        turns++
                        job = launch { provider.warmNext(position) }
                    }
                    delay(250)
                }
            } finally { job?.cancelAndJoin(); provider.cancelPending() }
            report.put("previewsEnabled", JSONObject().put("positionAdvancedMs", main { player!!.currentPosition } - enabledStart)
                .put("rebuffers", main { rebuffers }).put("droppedFrames", main { dropped } - enabledDrops)
                .put("warmTurns", turns).put("renderedFramesCaptured", captured))
            main { measuring = false; player!!.pause() }
            val target = (main { player!!.currentPosition } / 10_000L * 10_000L - 20_000L).coerceAtLeast(0)
            selectedPosition.value = target
            val coldStart = SystemClock.elapsedRealtime()
            val frame = provider.memoryFrameAt(target)
            report.put("renderedPreviewMs", SystemClock.elapsedRealtime() - coldStart).put("previewAvailable", frame != null)
            assertNotNull("Played debrid video must yield a validated renderer preview", frame)
            assertTrue(provider.matchesTarget(frame, target))
            selected.value = frame
            neighbors.value = seekPreviewWindow(target, duration).mapNotNull { provider.memoryFrameAt(it) }
            report.put("readyWindowFrames", neighbors.value.size)
            val times = (0 until 100).map {
                val start = System.nanoTime()
                assertNotNull(provider.memoryFrameAt(target))
                (System.nanoTime() - start) / 1_000_000.0
            }.sorted()
            report.put("cachedP95Ms", times[94])
            assertTrue(times[94] < 100)
            delay(500)
            val evidence = File(context.getExternalFilesDir(null), "preview-evidence").apply { mkdirs() }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(evidence, "live-debrid-window.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            provider.cancelPending()
            selected.value = null
            main { player!!.seekTo(120_000); player!!.play() }
            withTimeout(15_000) { while (!main { player!!.isPlaying && player!!.currentPosition >= 121_000 }) delay(250) }
            report.put("resumeAfterSeek", true).put("playerErrors", main { errors })
            assertEquals(0, main { errors })
            assertEquals("No new rebuffer during preview window", 0, report.getJSONObject("previewsEnabled").getInt("rebuffers"))
            assertTrue("Preview work must not materially increase frame drops",
                report.getJSONObject("previewsEnabled").getInt("droppedFrames") <=
                    report.getJSONObject("baseline").getInt("droppedFrames") * 1.5 + 10)
        } finally {
            File(context.getExternalFilesDir(null), "seek-stream-report.json").writeText(report.toString(2))
            provider.close()
            main { player?.release() }
            scenario.close()
        }
    }
}
