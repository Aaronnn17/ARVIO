package com.arflix.tv.ui.screens.tv.live

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import kotlin.math.roundToInt

/** Read in a graphicsLayer block to keep the video anchored at the right edge. */
internal val LocalLiveDrawerTranslation = staticCompositionLocalOf<() -> Float> { { 0f } }

/** Measure each viewport once per toggle; animation changes placement, not every EPG cell's width. */
@Composable
internal fun LiveDrawerWorkspace(
    expanded: Boolean,
    sidebar: @Composable () -> Unit,
    content: @Composable () -> Unit,
    contentKey: String = "guide",
    sidebarWidth: androidx.compose.ui.unit.Dp = LiveDims.SidebarExpanded,
) {
    val destinations = rememberSaveableStateHolder()
    val progress = animateFloatAsState(if (expanded) 1f else 0f, tween(200), label = "guide-drawer")
    val target = if (expanded) 1f else 0f
    val density = androidx.compose.ui.platform.LocalDensity.current
    val sidebarPixels = with(density) { sidebarWidth.toPx() }
    Layout(modifier = Modifier.fillMaxSize().clipToBounds(), content = {
        Box(Modifier.fillMaxSize()) { sidebar() }
        CompositionLocalProvider(LocalLiveDrawerTranslation provides { sidebarPixels * (progress.value - target) }) {
            Box(Modifier.fillMaxSize()) {
                destinations.SaveableStateProvider(contentKey) { content() }
            }
        }
    }) { children, constraints ->
        val sideWidth = sidebarPixels.roundToInt().coerceAtMost(constraints.maxWidth / 2)
        val reserved = if (expanded) sideWidth else 0
        val side = children[0].measure(Constraints.fixed(sideWidth, constraints.maxHeight))
        val body = children[1].measure(Constraints.fixed(constraints.maxWidth - reserved, constraints.maxHeight))
        layout(constraints.maxWidth, constraints.maxHeight) {
            val position = (sideWidth * progress.value).roundToInt()
            side.placeRelative(position - sideWidth, 0)
            body.placeRelative(position, 0)
        }
    }
}
