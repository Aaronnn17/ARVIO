package com.arflix.tv.ui.components

import android.view.LayoutInflater
import android.util.Log
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.arflix.tv.R
import com.arflix.tv.data.api.InAppYouTubeExtractor
import com.arflix.tv.data.api.YoutubeChunkedDataSourceFactory
import com.arflix.tv.data.api.YOUTUBE_TRAILER_USER_AGENT
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Muted YouTube trailer player using ExoPlayer with direct YouTube stream extraction.
 * Waits [delayMs] before resolving and playing (shows static backdrop first).
 * Uses TextureView (via layout XML) so AnimatedVisibility's fadeIn works without a black flash —
 * the view is transparent during the fade while ExoPlayer buffers in the background.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface TrailerPlayerEntryPoint {
    fun inAppYouTubeExtractor(): InAppYouTubeExtractor
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun TrailerPlayer(
    youtubeKey: String,
    modifier: Modifier = Modifier,
    delayMs: Long = 0L,
    volume: Float = 0f,
    onPlayingChanged: (Boolean) -> Unit = {}
) {
    val context = LocalContext.current
    val currentOnPlayingChanged by rememberUpdatedState(onPlayingChanged)

    var shouldPlay by remember { mutableStateOf(false) }
    var videoUrl by remember { mutableStateOf<String?>(null) }
    var audioUrl by remember { mutableStateOf<String?>(null) }
    var fallbackVideoUrl by remember { mutableStateOf<String?>(null) }

    val entryPoint = remember {
        EntryPointAccessors.fromApplication(context, TrailerPlayerEntryPoint::class.java)
    }
    val extractor = remember { entryPoint.inAppYouTubeExtractor() }

    LaunchedEffect(youtubeKey) {
        shouldPlay = false
        videoUrl = null
        audioUrl = null
        fallbackVideoUrl = null
        delay(delayMs)
        withContext(Dispatchers.IO) {
            try {
                val source = extractor.extractPlaybackSource("https://www.youtube.com/watch?v=$youtubeKey")
                if (source != null) {
                    videoUrl = source.videoUrl
                    audioUrl = source.audioUrl
                    fallbackVideoUrl = source.fallbackVideoUrl
                }
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                Log.w("TrailerQuality", "Trailer preparation failed (${error.javaClass.simpleName})")
            }
        }
        if (videoUrl != null) {
            shouldPlay = true
            currentOnPlayingChanged(true)
        } else {
            currentOnPlayingChanged(false)
        }
    }

    // TextureView (set via XML) means the view is transparent during the fade-in,
    // so the backdrop image shows through while ExoPlayer buffers. No black flash.
    AnimatedVisibility(
        visible = shouldPlay && videoUrl != null,
        enter = fadeIn(animationSpec = tween(800)),
        exit = fadeOut(),
        modifier = modifier
    ) {
        val player = remember(youtubeKey) {
            ExoPlayer.Builder(context)
                .setBandwidthMeter(DefaultBandwidthMeter.Builder(context)
                    .setInitialBitrateEstimate(8_000_000L).build())
                .build().apply {
                trackSelectionParameters = trackSelectionParameters.forFullHdTrailer()
                repeatMode = Player.REPEAT_MODE_OFF
                playWhenReady = true
            }
        }

        LaunchedEffect(volume) {
            player.volume = volume.coerceIn(0f, 1f)
        }

        LaunchedEffect(videoUrl, audioUrl, youtubeKey) {
            val vUrl = videoUrl ?: return@LaunchedEffect
            if (!audioUrl.isNullOrBlank()) {
                val factory = DefaultMediaSourceFactory(YoutubeChunkedDataSourceFactory())
                val videoSource = factory.createMediaSource(MediaItem.fromUri(vUrl))
                val audioSource = factory.createMediaSource(MediaItem.fromUri(audioUrl!!))
                player.setMediaSource(MergingMediaSource(videoSource, audioSource))
            } else {
                val factory = DefaultMediaSourceFactory(
                    androidx.media3.datasource.DefaultHttpDataSource.Factory()
                        .setUserAgent(YOUTUBE_TRAILER_USER_AGENT)
                )
                player.setMediaSource(factory.createMediaSource(MediaItem.fromUri(vUrl)))
            }
            player.prepare()
        }

        val lifecycleOwner = LocalLifecycleOwner.current
        DisposableEffect(lifecycleOwner, player) {
            val listener = object : Player.Listener {
                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    extractor.evictCache(youtubeKey)
                    val fallback = fallbackVideoUrl
                    if (fallback != null) {
                        fallbackVideoUrl = null
                        audioUrl = null
                        videoUrl = fallback
                    } else {
                        shouldPlay = false
                        currentOnPlayingChanged(false)
                    }
                }
                override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                    Log.i("TrailerQuality", "Native trailer ${videoSize.width}x${videoSize.height}")
                }
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_ENDED) {
                        shouldPlay = false
                        currentOnPlayingChanged(false)
                    }
                }
            }
            val observer = LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_PAUSE -> player.pause()
                    Lifecycle.Event.ON_RESUME -> if (shouldPlay) player.play()
                    else -> {}
                }
            }
            player.addListener(listener)
            lifecycleOwner.lifecycle.addObserver(observer)
            if (!lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                player.pause()
            }
            onDispose {
                lifecycleOwner.lifecycle.removeObserver(observer)
                player.removeListener(listener)
                currentOnPlayingChanged(false)
                player.stop()
                player.release()
            }
        }

        AndroidView(
            factory = { ctx ->
                (LayoutInflater.from(ctx).inflate(R.layout.trailer_player_view, null) as PlayerView).apply {
                    this.player = player
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    keepScreenOn = true
                }
            },
            update = { view ->
                if (view.player !== player) view.player = player
            },
            modifier = Modifier.fillMaxSize().clipToBounds()
        )
    }
}
