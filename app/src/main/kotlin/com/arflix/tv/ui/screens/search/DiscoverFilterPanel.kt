package com.arflix.tv.ui.screens.search

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.arflix.tv.ui.skin.resolveAccentColor
import com.arflix.tv.ui.theme.ArflixTypography
import com.arflix.tv.ui.theme.TextSecondary

/** One tickable value inside a filter panel. */
internal data class PanelOption(
    val key: String,
    val label: String,
    val isSelected: Boolean,
    val onToggle: () -> Unit
)

/**
 * What one open filter panel shows.
 *
 * [mode] is the "Match all / Match any" style switch that two of the panels carry; it is drawn
 * above the options and is not part of the focus grid, because a mode is set far less often
 * than a value and should not sit between the chip and the list.
 */
internal data class FilterPanelSpec(
    val id: DiscoverFilterId,
    val title: String,
    val subtitle: String? = null,
    val options: List<PanelOption>,
    val columns: Int = PANEL_COLUMNS,
    val mode: PanelMode? = null,
    val footer: String? = null
)

/** A two-way switch above a panel's options, such as "Match all / Match any". */
internal data class PanelMode(
    val leftLabel: String,
    val rightLabel: String,
    val isLeftSelected: Boolean,
    val onSelect: (Boolean) -> Unit
)

/** Three across, as in the approved draft — wide enough for "Documentary", narrow enough to scan. */
internal const val PANEL_COLUMNS = 3

/**
 * The panel that opens under a filter chip on a TV, and rises from the bottom edge on a phone.
 *
 * Focus works the way it does everywhere else on this screen: the caller owns the index and the
 * panel only paints it. [focusedOption] is `null` on a touch device, where the panel is tapped.
 */
@Composable
internal fun DiscoverFilterPanel(
    spec: FilterPanelSpec,
    focusedOption: Int?,
    isTouchDevice: Boolean,
    modifier: Modifier = Modifier
) {
    val gridState = rememberLazyGridState()
    LaunchedEffect(focusedOption) {
        val target = focusedOption ?: return@LaunchedEffect
        if (target in spec.options.indices) gridState.animateScrollToItem(target)
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xFF101012), RoundedCornerShape(12.dp))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(horizontal = 18.dp, vertical = 14.dp)
            .testTag("filter-panel-${spec.id}")
    ) {
        PanelHeader(spec)
        spec.mode?.let { PanelModeSwitch(it, isTouchDevice) }
        LazyVerticalGrid(
            state = gridState,
            columns = GridCells.Fixed(spec.columns),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth().heightIn(max = 260.dp).padding(top = 10.dp)
        ) {
            itemsIndexed(spec.options, key = { _, option -> option.key }) { index, option ->
                PanelOptionChip(
                    option = option,
                    isVisuallyFocused = !isTouchDevice && focusedOption == index,
                    isTouchDevice = isTouchDevice
                )
            }
        }
        spec.footer?.let {
            Text(
                it,
                style = ArflixTypography.caption.copy(fontSize = 11.sp),
                color = TextSecondary,
                modifier = Modifier.padding(top = 10.dp)
            )
        }
    }
}

@Composable
private fun PanelHeader(spec: FilterPanelSpec) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(
            spec.title,
            style = ArflixTypography.body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
            color = Color.White
        )
        spec.subtitle?.let {
            Text(
                "  ·  $it",
                style = ArflixTypography.caption.copy(fontSize = 12.sp),
                color = TextSecondary
            )
        }
    }
}

@Composable
private fun PanelModeSwitch(mode: PanelMode, isTouchDevice: Boolean) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(top = 10.dp)
    ) {
        listOf(mode.leftLabel to true, mode.rightLabel to false).forEach { (label, isLeft) ->
            val selected = mode.isLeftSelected == isLeft
            Box(
                modifier = Modifier
                    .background(
                        if (selected) Color.White.copy(alpha = 0.92f) else Color.White.copy(alpha = 0.075f),
                        RoundedCornerShape(6.dp)
                    )
                    .then(if (isTouchDevice) Modifier.clickable { mode.onSelect(isLeft) } else Modifier)
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text(
                    label,
                    style = ArflixTypography.caption.copy(fontSize = 11.sp),
                    color = if (selected) Color.Black else TextSecondary
                )
            }
        }
    }
}

@Composable
private fun PanelOptionChip(option: PanelOption, isVisuallyFocused: Boolean, isTouchDevice: Boolean) {
    val accent = resolveAccentColor(fallback = Color.White)
    val shape = RoundedCornerShape(8.dp)
    val background = when {
        isVisuallyFocused -> Color.White.copy(alpha = 0.16f)
        option.isSelected -> Color.White.copy(alpha = 0.92f)
        else -> Color.White.copy(alpha = 0.06f)
    }
    val foreground = if (option.isSelected && !isVisuallyFocused) Color.Black else Color.White
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { selected = option.isSelected; role = Role.Checkbox }
            .background(background, shape)
            .border(
                if (isVisuallyFocused) 2.dp else 1.dp,
                if (isVisuallyFocused) accent else Color.White.copy(alpha = 0.18f),
                shape
            )
            .then(if (isTouchDevice) Modifier.clickable { option.onToggle() } else Modifier)
            .padding(horizontal = 12.dp, vertical = 9.dp)
            .testTag("filter-option-${option.key}")
    ) {
        Text(
            option.label,
            style = ArflixTypography.caption.copy(fontSize = 12.sp),
            color = foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
