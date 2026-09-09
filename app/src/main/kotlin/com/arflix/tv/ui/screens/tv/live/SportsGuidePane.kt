package com.arflix.tv.ui.screens.tv.live

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import coil.compose.AsyncImage
import com.arflix.tv.R
import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.ui.focus.mirrorHorizontalForRtl
import androidx.compose.ui.unit.LayoutDirection
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date

internal const val SPORTS_GUIDE_CATEGORY = "sports-hub"

internal fun LiveCategoryTree.withSportsDestination(): LiveCategoryTree = copy(
    top = top.filterNot { it.id == SPORTS_GUIDE_CATEGORY }.flatMap { category ->
        if (category.id == "all") listOf(category, LiveCategory(SPORTS_GUIDE_CATEGORY, "Sports", 0, CategoryIcon.Sport))
        else listOf(category)
    },
)

@Composable
internal fun SportsGuidePane(
    events: List<SportsGuideEvent>,
    now: Long,
    loading: Boolean,
    focusSignal: Int,
    onContentFocused: () -> Unit,
    onOpenCategories: () -> Unit,
    onPlay: (IptvChannel) -> Unit,
    modifier: Modifier = Modifier,
    failed: Boolean = false,
    onRetry: () -> Unit = {},
    providerNames: Map<String, String> = emptyMap(),
    sidebarOpen: Boolean = false,
) {
    val rows = remember(events, now) { sportsGuideRows(events, now) }
    var selected by remember { mutableStateOf<SportsGuideEvent?>(null) }
    var returnFocus by remember { mutableStateOf<FocusRequester?>(null) }
    val firstFocus = remember { FocusRequester() }
    val isRtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val narrow = configuration.screenWidthDp < 600
    val timeFormat = remember(context) { android.text.format.DateFormat.getTimeFormat(context) }
    val today = Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault()).toLocalDate()
    fun eventTime(event: SportsGuideEvent): String {
        if (event.isOnAir(now)) return "ON AIR"
        val date = Instant.ofEpochMilli(event.programme.startUtcMillis).atZone(ZoneId.systemDefault())
        val day = when (date.toLocalDate()) {
            today -> "Today"
            today.plusDays(1) -> "Tomorrow"
            else -> date.format(DateTimeFormatter.ofPattern("EEE d MMM"))
        }
        return "$day ${timeFormat.format(Date(event.programme.startUtcMillis))}"
    }
    LaunchedEffect(focusSignal, rows.isEmpty()) {
        if (focusSignal > 0) runCatching { firstFocus.requestFocus() }
    }
    LaunchedEffect(selected) {
        if (selected == null) returnFocus?.let { runCatching { it.requestFocus() } }
    }
    CompositionLocalProvider(LocalTextStyle provides LocalTextStyle.current.copy(fontFamily = LiveFontFamily)) {
    BoxWithConstraints(modifier.fillMaxSize().background(LiveColors.Bg)) {
    // Keep card geometry stable while the drawer moves; cached lazy rows must not
    // retain the wider three-column measurement after a four-column expansion.
    val viewport = configuration.screenWidthDp.dp
    val columns = when { viewport >= 850.dp -> 4; viewport >= 620.dp -> 3; viewport >= 420.dp -> 2; else -> 1 }
    val cardWidth = if (columns == 1) viewport - 54.dp else (viewport - 36.dp - 12.dp * (columns - 1)) / columns
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.height(32.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!sidebarOpen) Icon(Icons.Outlined.Menu, "Categories", tint = LiveColors.Fg,
                modifier = Modifier.size(20.dp).clickable(onClick = onOpenCategories))
            Text("Sports", color = LiveColors.Fg, fontSize = 21.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold)
        }
        if (rows.isEmpty()) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally) {
                if (loading) CircularProgressIndicator(color = LiveColors.Accent, modifier = Modifier.size(24.dp))
                else Icon(Icons.Default.SportsSoccer, null, tint = LiveColors.FgDim, modifier = Modifier.size(32.dp))
                Text(if (loading) "Reading sports schedule" else if (failed) "Schedule unavailable" else "No sports events in the available guide",
                    color = LiveColors.FgDim, modifier = Modifier.padding(14.dp))
                if (failed) Text("Retry", color = LiveColors.Fg,
                    modifier = Modifier.clickable(onClick = onRetry).padding(16.dp))
                Text("Categories", color = LiveColors.Fg, modifier = Modifier.focusRequester(firstFocus)
                    .clickable(onClick = onOpenCategories).padding(16.dp))
            }
        } else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(rows, key = { _, row -> row.id }) { rowIndex, row ->
                Column {
                    Row(Modifier.fillMaxWidth().height(if (narrow) 44.dp else 20.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(row.title, color = LiveColors.Fg, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 18.sp,
                            modifier = Modifier.weight(1f))
                    }
                    LazyRow(Modifier.padding(horizontal = 18.dp), contentPadding = PaddingValues(vertical = 1.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        itemsIndexed(row.events, key = { _, event -> event.id }) { index, event ->
                            val requester = remember { FocusRequester() }
                            var focused by remember { mutableStateOf(false) }
                            Column(Modifier.width(cardWidth).testTag("sports-event-card")
                                .then(if (index == 0 && rowIndex == 0) Modifier.focusRequester(firstFocus) else Modifier)
                                .focusRequester(requester)
                                .onFocusChanged { focused = it.isFocused; if (it.isFocused) onContentFocused() }
                                .onPreviewKeyEvent { key ->
                                    if (index == 0 && key.type == KeyEventType.KeyDown &&
                                        key.key.mirrorHorizontalForRtl(isRtl) == Key.DirectionLeft) {
                                        onOpenCategories(); true
                                    } else false
                                }
                                .clickable { returnFocus = requester; selected = event }
                                .padding(2.dp)) {
                                Box(Modifier.fillMaxWidth().aspectRatio(if (row.id == "more") 2.85f else 2.25f).clip(RoundedCornerShape(4.dp))) {
                                    EventArtwork(event, Modifier.fillMaxSize())
                                    Row(Modifier.padding(6.dp).background(Color.Black.copy(alpha = .85f), RoundedCornerShape(3.dp))
                                        .padding(horizontal = 5.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                        if (event.isOnAir(now)) Box(Modifier.padding(end = 4.dp).size(7.dp).background(LiveColors.LiveRed, RoundedCornerShape(50)))
                                        Text(eventTime(event), color = Color.White, fontSize = 10.sp, lineHeight = 12.sp)
                                    }
                                    Box(Modifier.matchParentSize().border(2.dp, if (focused) Color.White else Color.Transparent, RoundedCornerShape(4.dp)))
                                }
                                Text(event.title, color = LiveColors.Fg, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.padding(top = 4.dp))
                                Row(Modifier.fillMaxWidth().height(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(listOfNotNull(event.sport.title, event.competition).joinToString(" · "), color = LiveColors.FgDim, fontSize = 10.sp, lineHeight = 13.sp,
                                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                    if (event.isOnAir(now)) {
                                        Icon(Icons.Default.Tv, null, tint = LiveColors.FgDim, modifier = Modifier.size(13.dp))
                                        Text(channelCount(event.availableChannels(now).size), color = LiveColors.FgDim, fontSize = 9.sp, lineHeight = 12.sp,
                                            modifier = Modifier.padding(start = 6.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
    val event = selected?.let { selection -> events.firstOrNull { it.id == selection.id } }
    fun dismiss() { selected = null }
    if (selected != null) Dialog(onDismissRequest = ::dismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            window?.setDimAmount(.65f)
        }
        val onAir = event?.isOnAir(now) == true
        val sourceChannels = if (onAir) event?.availableChannels(now).orEmpty() else event?.channels.orEmpty()
        val initialFocus = remember(event?.id) { FocusRequester() }
        LaunchedEffect(event?.id) {
            // The native dialog window must own focus before Compose assigns its row.
            withFrameNanos { }
            withFrameNanos { }
            initialFocus.requestFocus()
        }
        Column(Modifier.widthIn(max = 586.dp).fillMaxWidth().heightIn(max = configuration.screenHeightDp.dp * .82f)
            .border(1.dp, LiveColors.DividerStrong, RoundedCornerShape(5.dp))
            .clip(RoundedCornerShape(5.dp)).background(LiveColors.Panel).padding(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                EventArtwork(event ?: selected!!, Modifier.size(if (narrow) 84.dp else 132.dp, 58.dp).clip(RoundedCornerShape(3.dp)))
                Column(Modifier.weight(1f).padding(start = 14.dp)) {
                    Text(listOfNotNull(event?.let(::eventTime), event?.sport?.title).joinToString("  ·  "),
                        color = LiveColors.FgDim, fontSize = 11.sp)
                    Text(event?.title ?: selected!!.title, fontSize = 18.sp, lineHeight = 21.sp, maxLines = 2,
                        overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold, color = LiveColors.Fg,
                        modifier = Modifier.padding(top = 7.dp))
                }
                Icon(Icons.Default.Close, "Close", tint = LiveColors.Fg,
                    modifier = Modifier.size(44.dp)
                        .then(if (!onAir || sourceChannels.isEmpty()) Modifier.focusRequester(initialFocus) else Modifier)
                        .clickable(onClick = ::dismiss).padding(10.dp))
            }
            Row(Modifier.fillMaxWidth().padding(top = 9.dp, bottom = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (onAir) "Available channels" else "Scheduled channels", fontSize = 14.sp, color = LiveColors.Fg,
                    fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                Text(channelCount(sourceChannels.size), fontSize = 11.sp, color = LiveColors.FgDim)
            }
            LazyColumn(Modifier.heightIn(max = (if (narrow) 49.dp else 41.dp) * sourceChannels.size.coerceIn(1, 20))) {
                itemsIndexed(sourceChannels, key = { _, channel -> channel.id }) { index, channel ->
                    var focused by remember { mutableStateOf(false) }
                    Row(Modifier.fillMaxWidth().heightIn(min = if (narrow) 48.dp else 40.dp).clip(RoundedCornerShape(4.dp))
                        .then(if (index == 0 && onAir) Modifier.focusRequester(initialFocus) else Modifier)
                        .border(1.dp, if (focused) Color.White else Color.Transparent, RoundedCornerShape(4.dp))
                        .background(if (focused) LiveColors.FocusBg else Color.Transparent)
                        .onFocusChanged { focused = it.isFocused }
                        .clickable(enabled = onAir) {
                            if (event?.availableChannels(System.currentTimeMillis())?.any { it.id == channel.id } == true) { dismiss(); onPlay(channel) }
                        }.padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        if (channel.logo.isNullOrBlank()) Box(Modifier.size(if (narrow) 40.dp else 88.dp, 30.dp), contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Tv, null, tint = LiveColors.FgDim, modifier = Modifier.size(24.dp))
                        }
                        else AsyncImage(channel.logo, null, contentScale = ContentScale.Fit, modifier = Modifier.size(if (narrow) 40.dp else 88.dp, 30.dp))
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            Text(channel.name, color = LiveColors.Fg, fontSize = 13.sp, lineHeight = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            val provider = providerNames[channelPlaylistId(channel.id)]
                            Text(provider ?: channel.group.orEmpty(), color = LiveColors.FgDim, fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        val enriched = remember(channel) { channel.enrich(0) }
                        if (enriched.quality != Quality.UNKNOWN) PickerBadge(enriched.quality.label)
                        // EN was a guessed fallback, not provider metadata.
                        channel.language?.takeIf { it.isNotBlank() }?.let { PickerBadge(it.uppercase()) }
                        Icon(if (focused) Icons.Default.PlayArrow else Icons.Outlined.ChevronRight, null,
                            tint = LiveColors.Fg, modifier = Modifier.padding(start = 12.dp).size(18.dp))
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(LiveColors.Divider))
                }
            }
            if (event == null) Text("This event is no longer in the available guide.", color = LiveColors.FgDim)
        }
    }
    }
}

private fun channelCount(count: Int) = "$count ${if (count == 1) "channel" else "channels"}"

@Composable
private fun EventArtwork(event: SportsGuideEvent, modifier: Modifier = Modifier) {
    var loaded by remember(event.artwork) { mutableStateOf(false) }
    var fallbackLoaded by remember(event.sport) { mutableStateOf(false) }
    Box(modifier.background(LiveColors.Panel).testTag(if (loaded) "sports-artwork-loaded" else "sports-artwork-pending")) {
        if (!loaded) {
            // Bundled sport photography is explicitly a fallback, never an invented event banner.
            AsyncImage(event.sport.fallbackArtwork(), null, contentScale = ContentScale.Crop,
                onSuccess = { fallbackLoaded = true },
                modifier = Modifier.fillMaxSize().testTag(if (fallbackLoaded) "sports-artwork-fallback-loaded" else "sports-artwork-fallback"))
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Color.Black.copy(alpha = .72f))
                .padding(horizontal = 10.dp, vertical = 5.dp)) {
                Text(event.title, color = LiveColors.Fg, fontSize = 11.sp, lineHeight = 13.sp,
                    fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        event.artwork?.let { url ->
            AsyncImage(url, null, contentScale = ContentScale.Fit,
                onSuccess = { loaded = true }, onError = { loaded = false },
                modifier = Modifier.fillMaxSize())
        }
    }
}

private fun GuideSport.fallbackArtwork(): Int = when (this) {
    GuideSport.FOOTBALL -> R.drawable.sports_card_football
    GuideSport.BASKETBALL -> R.drawable.sports_card_basketball
    GuideSport.F1 -> R.drawable.sports_card_motor_sports
    GuideSport.TENNIS -> R.drawable.sports_card_tennis
    GuideSport.MMA, GuideSport.BOXING -> R.drawable.sports_card_fight
    GuideSport.AMERICAN_FOOTBALL -> R.drawable.sports_card_american_football
    GuideSport.CRICKET -> R.drawable.sports_card_cricket
    GuideSport.BASEBALL -> R.drawable.sports_card_baseball
    GuideSport.HOCKEY -> R.drawable.sports_card_hockey
}

@Composable
private fun PickerBadge(label: String) {
    Text(label, color = LiveColors.Fg, fontSize = 10.sp, lineHeight = 12.sp, modifier = Modifier.padding(start = 8.dp)
        .border(1.dp, LiveColors.DividerStrong, RoundedCornerShape(3.dp)).background(LiveColors.Bg)
        .padding(horizontal = 7.dp, vertical = 3.dp))
}
