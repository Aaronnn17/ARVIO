package com.arflix.tv.ui.screens.player.preview

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Callers validate source identity; this also rejects stale positions during touch recomposition. */
@Composable
fun ReadySeekPreview(
    frame: SeekPreviewFrame?,
    positionMs: Long,
    modifier: Modifier = Modifier,
    visible: Boolean = true,
    sourceGeneration: Long = frame?.sourceGeneration ?: -1L,
    cornerRadius: Dp = 5.dp,
) {
    if (!visible || frame == null || frame.bitmap.isRecycled ||
        !frame.isValidFor(positionMs, sourceGeneration)) return

    // Fade in only. Retaining outgoing content or crossfading would show the previous target.
    val opacity = remember { Animatable(0f) }
    LaunchedEffect(Unit) { opacity.animateTo(1f, tween(80)) }
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .testTag("seek_preview_ready")
            .graphicsLayer { alpha = opacity.value }
            .shadow(14.dp, shape, clip = false)
            .aspectRatio(16f / 9f)
            .background(Color.Black, shape)
            .border(1.dp, Color.White.copy(alpha = 0.68f), shape)
            .clip(shape)
    ) {
        Image(
            bitmap = frame.bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
