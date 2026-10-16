package com.arflix.tv.ui.screens.home

import android.os.SystemClock
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants
import coil.request.ImageRequest
import coil.size.Precision
import com.arflix.tv.R
import com.arflix.tv.data.model.Category
import com.arflix.tv.data.model.MediaItem
import com.arflix.tv.data.model.MediaType
import com.arflix.tv.data.model.isPortrait
import com.arflix.tv.ui.components.AppTopBarHeight
import com.arflix.tv.ui.components.CardLayoutMode
import com.arflix.tv.ui.components.HomeTrailerPreview
import com.arflix.tv.ui.components.MediaCard
import com.arflix.tv.ui.components.rememberCatalogueRowLayoutMode
import com.arflix.tv.ui.theme.ArflixTypography
import com.arflix.tv.util.TmdbImageSizing
import kotlin.math.abs
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.LayoutCoordinates

/** What the Netflix-style TV Home draws beyond the classic rows. Null selects the classic Home. */
@Immutable
internal data class NetflixHomeContent(
    val billboardItem: MediaItem?,
    val billboardLogoUrl: String?,
    val billboardTrailerKey: String?,
    /** The ViewModel hero: the focused card with its loaded details (overview, runtime...). */
    val featuredItem: MediaItem?,
    val cardTrailerKey: String?,
    val cardTrailerDelayMs: Long,
    val trailerVolume: Float,
    /** The ViewModel hero's overview; for a channel, the programme on air. */
    val featuredOverview: String? = null,
    /**
     * The hero preview player while a channel is the hero ([channelPreviewItem]). Channel
     * cards share one surface on it: many IPTV streams rarely send keyframes, so moving the
     * decoder to a new surface would leave the video black under playing audio.
     */
    val channelPreviewPlayer: androidx.media3.exoplayer.ExoPlayer? = null,
    val channelPreviewItem: MediaItem? = null
)

private val NETFLIX_BILLBOARD_TOP10_IDS = setOf("top10_movies_today", "top10_shows_today")
private val NETFLIX_BILLBOARD_TRENDING_IDS = setOf("trending_movies", "trending_tv")

/**
 * Billboard candidates: today's Top 10 movies and series. When those rows are hidden,
 * any other Top 10 row, then the trending rows.
 */
internal fun netflixBillboardCandidates(
    categories: List<Category>,
    isSpecialItem: (MediaItem) -> Boolean
): List<MediaItem> {
    fun itemsOf(rows: List<Category>) = rows.asSequence()
        .flatMap { it.items.asSequence() }
        .filter { isActionableHomeItem(it) && !isSpecialItem(it) && !it.backdrop.isNullOrBlank() }
        .distinctBy { homeRowItemKey(it) }
        .toList()

    val isOtherTop10 = { category: Category ->
        category.id.contains("top10", ignoreCase = true) ||
            category.title.contains("Top 10", ignoreCase = true)
    }
    return sequenceOf<(Category) -> Boolean>(
        { it.id in NETFLIX_BILLBOARD_TOP10_IDS },
        isOtherTop10,
        { it.id in NETFLIX_BILLBOARD_TRENDING_IDS }
    )
        .map { matches -> itemsOf(categories.filter(matches)) }
        .firstOrNull { it.isNotEmpty() }
        .orEmpty()
}

/**
 * D-pad handling the Netflix layout adds on top of the classic Home: the billboard is a
 * focus stop between the top bar and the first row. Returns null for keys it leaves to
 * the classic handler.
 */
internal fun handleNetflixHomeKey(
    event: KeyEvent,
    netflix: NetflixHomeContent,
    focusState: HomeFocusState,
    categories: List<Category>,
    isRtl: Boolean,
    onBillboardOpen: (MediaItem, Boolean) -> Unit,
    onOpenContextMenu: (MediaItem, Boolean) -> Unit
): Boolean? {
    val keyDown = event.type == KeyEventType.KeyDown
    val isSelect = event.key == Key.Enter || event.key == Key.DirectionCenter
    val isBack = event.key == Key.Back || event.key == Key.Escape
    val now = SystemClock.elapsedRealtime()
    val billboardFocused = focusState.isHeroFocused && !focusState.isSidebarFocused

    if (billboardFocused) {
        if (!keyDown) return if (isSelect) true else null
        return when (event.key) {
            Key.DirectionLeft, Key.DirectionRight -> {
                val forward = (event.key == Key.DirectionRight) != isRtl
                focusState.heroButtonIndex = if (forward) 1 else 0
                focusState.userHasNavigated = true
                focusState.lastNavEventTime = now
                true
            }
            Key.DirectionUp -> {
                focusState.userHasNavigated = true
                focusState.isSidebarFocused = true
                focusState.lastNavEventTime = now
                true
            }
            Key.DirectionDown -> {
                val firstRow = categories.firstOrNull() ?: return true
                focusState.userHasNavigated = true
                focusState.isHeroFocused = false
                focusState.currentRowIndex = 0
                focusState.currentItemIndex = focusState.restoredItemIndex(
                    firstRow,
                    focusState.rowItemIndicesByCategoryId[firstRow.id] ?: 0
                )
                focusState.lastNavEventTime = now
                true
            }
            Key.Enter, Key.DirectionCenter -> {
                if (event.nativeKeyEvent.repeatCount == 0) {
                    netflix.billboardItem?.takeIf { isActionableHomeItem(it) }
                        ?.let { onBillboardOpen(it, focusState.heroButtonIndex == 0) }
                }
                true
            }
            Key.Menu, Key.Info -> {
                netflix.billboardItem?.takeIf { isActionableHomeItem(it) }
                    ?.let { onOpenContextMenu(it, false) }
                true
            }
            Key.Back, Key.Escape -> {
                focusState.isSidebarFocused = true
                true
            }
            else -> null
        }
    }

    if (!keyDown) return null

    // The top bar above the billboard: Down returns to the billboard, not a row.
    if (focusState.isSidebarFocused && focusState.isHeroFocused && event.key == Key.DirectionDown) {
        focusState.isSidebarFocused = false
        focusState.lastNavEventTime = now
        return true
    }

    // A row: Up from the first row and Back both scroll back to the billboard.
    val rowFocused = !focusState.isSidebarFocused && !focusState.isHeroFocused
    val toBillboard = (event.key == Key.DirectionUp && focusState.currentRowIndex == 0) || isBack
    if (rowFocused && toBillboard && netflix.billboardItem != null) {
        categories.getOrNull(focusState.currentRowIndex)?.id?.let { categoryId ->
            focusState.rowItemIndicesByCategoryId[categoryId] = focusState.currentItemIndex
        }
        focusState.recordSelection(categories)
        focusState.userHasNavigated = true
        focusState.isHeroFocused = true
        focusState.heroButtonIndex = 0
        focusState.lastNavEventTime = now
        return true
    }
    return null
}

/** TV rows for the Netflix layout: the billboard scrolls with the rows as their first item. */
@Composable
internal fun NetflixTvHomeRowsLayer(
    categories: List<Category>,
    cardLogoUrls: Map<String, String>,
    focusState: HomeFocusState,
    contentStartPadding: Dp,
    categoryHasMoreMap: Map<String, Boolean>,
    smoothScrolling: Boolean,
    onLoadMoreCategory: (String) -> Unit,
    onViewAllCategory: (String) -> Unit,
    netflix: NetflixHomeContent,
    isSpecialItem: (MediaItem) -> Boolean,
    onItemClick: (MediaItem) -> Unit
) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val screenHeight = maxHeight
        val topInset = AppTopBarHeight + 6.dp
        // About 70% of the screen, leaving the first row's title and the top of
        // its cards peeking below it.
        val billboardHeight = (maxHeight - topInset - 70.dp).coerceAtLeast(200.dp)
        // Focused-row card height: room for the row title above, the description
        // below and a peek of the next row.
        val bigCardHeight = (maxHeight * 0.42f).coerceIn(170.dp, 330.dp)
        val listState = rememberLazyListState()
        val targetIndex = if (focusState.isHeroFocused) 0 else focusState.currentRowIndex + 1
        val focusedRowId = if (focusState.isHeroFocused) null else categories.getOrNull(focusState.currentRowIndex)?.id
        var appliedTarget by remember { mutableIntStateOf(-1) }
        LaunchedEffect(targetIndex, focusedRowId) {
            if (appliedTarget < 0 || abs(targetIndex - listState.firstVisibleItemIndex) > 4) {
                listState.scrollToItem(targetIndex)
            } else {
                listState.animateScrollToItem(targetIndex)
            }
            appliedTarget = targetIndex
        }
        // Rows inserted or removed above the focused one (late catalog / channel loads)
        // shift the list under a keyed LazyColumn: re-anchor to the focused row.
        LaunchedEffect(categories) {
            if (appliedTarget >= 0 && !listState.isScrollInProgress &&
                listState.firstVisibleItemIndex != targetIndex
            ) {
                listState.scrollToItem(targetIndex)
            }
        }

        // Where the focused channel card's media area is, relative to this layer.
        var layerCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
        var channelMediaBounds by remember { mutableStateOf<Rect?>(null) }
        val onChannelCardPlaced: (LayoutCoordinates) -> Unit = { card ->
            layerCoordinates?.takeIf { it.isAttached && card.isAttached }?.let { layer ->
                channelMediaBounds = layer.localBoundingBoxOf(card, clipBounds = false)
            }
        }
        val focusedChannel = if (!focusState.isSidebarFocused && !focusState.isHeroFocused) {
            categories.getOrNull(focusState.currentRowIndex)
                ?.let { row -> navigableHomeItems(row.items).getOrNull(focusState.currentItemIndex) }
                ?.takeIf { it.isIptvChannel() }
        } else null

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = topInset)
                .clipToBounds()
                .onGloballyPositioned { layerCoordinates = it }
        ) {
            LazyColumn(
                state = listState,
                userScrollEnabled = false,
                // Lets the last row scroll up to the top like every other row.
                contentPadding = PaddingValues(bottom = screenHeight),
                modifier = Modifier.fillMaxSize()
            ) {
                item(key = "netflix_billboard", contentType = "netflix_billboard") {
                    NetflixBillboard(
                        item = netflix.billboardItem,
                        logoUrl = netflix.billboardLogoUrl,
                        trailerKey = netflix.billboardTrailerKey,
                        trailerVolume = netflix.trailerVolume,
                        isFocused = focusState.isHeroFocused && !focusState.isSidebarFocused,
                        focusedButton = focusState.heroButtonIndex,
                        horizontalPadding = contentStartPadding,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(billboardHeight)
                    )
                    Spacer(Modifier.height(14.dp))
                }
                itemsIndexed(
                    items = categories,
                    key = { _, category -> stableHomeRowKey("netflix", category.id) },
                    contentType = { _, category ->
                        if (netflixRowIsSpecial(category, isSpecialItem)) "netflix_special_row" else "netflix_row"
                    }
                ) { rowIndex, category ->
                    val rowIsFocused = !focusState.isSidebarFocused && !focusState.isHeroFocused &&
                        rowIndex == focusState.currentRowIndex
                    val rowHasMore = categoryHasMoreMap[category.id] == true
                    val viewAllIndex = remember(category.items, rowHasMore) {
                        homeRowViewAllIndex(category, rowHasMore)
                    }
                    val focusedItemIndex = when {
                        !rowIsFocused -> -1
                        viewAllIndex >= 0 && focusState.currentItemIndex == viewAllIndex -> viewAllIndex
                        else -> clampHomeItemIndex(category.items, focusState.currentItemIndex)
                    }
                    val onRowLoadMore = remember(category.id) { { onLoadMoreCategory(category.id) } }
                    val onRowViewAll = remember(category.id) { { onViewAllCategory(category.id) } }
                    val rowUsePosterCards =
                        rememberCatalogueRowLayoutMode("home:${category.id}") == CardLayoutMode.POSTER
                    if (netflixRowIsSpecial(category, isSpecialItem)) {
                        // Channel, service and sports tiles have no backdrop/overview to
                        // expand into: they keep the classic rail.
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(if (category.isPortrait(rowUsePosterCards)) 245.dp else 202.dp)
                                .clipToBounds()
                        ) {
                            ContentRow(
                                category = category,
                                cardLogoUrls = cardLogoUrls,
                                isCurrentRow = rowIsFocused,
                                usePosterCards = rowUsePosterCards,
                                startPadding = contentStartPadding,
                                categoryHasMore = rowHasMore,
                                smoothScrolling = smoothScrolling,
                                onLoadMore = onRowLoadMore,
                                showViewAll = viewAllIndex >= 0,
                                onViewAll = onRowViewAll,
                                focusedItemIndex = focusedItemIndex,
                                isFastScrolling = false,
                                onItemClick = onItemClick,
                                onItemFocused = { _, _ -> }
                            )
                        }
                    } else {
                        NetflixContentRow(
                            category = category,
                            cardLogoUrls = cardLogoUrls,
                            isCurrentRow = rowIsFocused,
                            focusedItemIndex = focusedItemIndex,
                            restingItemIndex = focusState.rowItemIndicesByCategoryId[category.id] ?: 0,
                            usePosterCards = rowUsePosterCards,
                            bigCardHeight = bigCardHeight,
                            startPadding = contentStartPadding,
                            categoryHasMore = rowHasMore,
                            showViewAll = viewAllIndex >= 0,
                            featuredItem = netflix.featuredItem,
                            featuredOverview = netflix.featuredOverview,
                            onChannelCardPlaced = onChannelCardPlaced,
                            trailerKey = if (rowIsFocused) netflix.cardTrailerKey else null,
                            trailerDelayMs = netflix.cardTrailerDelayMs,
                            trailerVolume = netflix.trailerVolume,
                            onLoadMore = onRowLoadMore,
                            onViewAll = onRowViewAll,
                            onItemClick = onItemClick
                        )
                    }
                }
            }
            // One surface for every channel card (see NetflixHomeContent.channelPreviewPlayer):
            // it follows focus along the row instead of each card creating its own.
            val previewPlayer = netflix.channelPreviewPlayer
            val bounds = channelMediaBounds
            if (focusedChannel != null && previewPlayer != null && bounds != null) {
                val density = LocalDensity.current
                NetflixChannelPreview(
                    player = previewPlayer,
                    focusedItem = focusedChannel,
                    streamItem = netflix.channelPreviewItem,
                    modifier = Modifier
                        // Measured bounds are physical (from the left edge); anchor there in RTL too.
                        .align(AbsoluteAlignment.TopLeft)
                        .absoluteOffset { IntOffset(bounds.left.roundToInt(), bounds.top.roundToInt()) }
                        .size(with(density) { bounds.width.toDp() }, with(density) { bounds.height.toDp() })
                )
            }
        }
    }
}

private fun netflixRowIsSpecial(category: Category, isSpecialItem: (MediaItem) -> Boolean): Boolean =
    category.id.startsWith("collection_row_") ||
        category.items.firstOrNull { !it.isPlaceholder }?.let(isSpecialItem) == true

@Composable
private fun NetflixBillboard(
    item: MediaItem?,
    logoUrl: String?,
    trailerKey: String?,
    trailerVolume: Float,
    isFocused: Boolean,
    focusedButton: Int,
    horizontalPadding: Dp,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val shape = RoundedCornerShape(16.dp)
    val borderAlpha by animateFloatAsState(
        targetValue = if (isFocused) 0.85f else 0.12f,
        animationSpec = tween(160),
        label = "netflix-billboard-border"
    )
    Box(modifier = modifier.padding(horizontal = horizontalPadding).testTag("netflix_billboard")) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .border(2.dp, Color.White.copy(alpha = borderAlpha), shape)
                // The border stays outside the media, which must not be covered.
                .padding(3.dp)
                .clip(RoundedCornerShape(13.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            // The trailer and artwork fill the width at 16:9; the billboard crops them.
            val mediaWidth = maxWidth
            val mediaHeight = maxOf(maxHeight, maxWidth * (9f / 16f))
            val backdropRequest = remember(item?.backdrop, item?.image, mediaWidth, mediaHeight) {
                val url = (item?.backdrop ?: item?.image)?.takeIf { it.isNotBlank() }
                url?.let {
                    val widthPx = with(density) { mediaWidth.roundToPx() }.coerceAtLeast(1)
                    val heightPx = with(density) { mediaHeight.roundToPx() }.coerceAtLeast(1)
                    ImageRequest.Builder(context)
                        .data(TmdbImageSizing.forSlot(it, widthPx, heightPx, TmdbImageSizing.Kind.BACKDROP))
                        .size(widthPx, heightPx)
                        .precision(Precision.INEXACT)
                        .crossfade(250)
                        .build()
                }
            }
            HomeTrailerPreview(
                youtubeKey = trailerKey,
                delayMs = 0L,
                volume = trailerVolume,
                modifier = Modifier.requiredSize(mediaWidth, mediaHeight)
            ) {
                if (backdropRequest != null) {
                    AsyncImage(
                        model = backdropRequest,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }

            if (item != null) {
                val isRtl = LocalLayoutDirection.current == LayoutDirection.Rtl
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .drawWithCache {
                            val start = if (isRtl) size.width else 0f
                            val end = if (isRtl) 0f else size.width
                            val sideScrim = Brush.horizontalGradient(
                                0f to Color.Black.copy(alpha = 0.82f),
                                0.35f to Color.Black.copy(alpha = 0.5f),
                                0.6f to Color.Transparent,
                                startX = start,
                                endX = end
                            )
                            val bottomScrim = Brush.verticalGradient(
                                0.55f to Color.Transparent,
                                1f to Color.Black.copy(alpha = 0.7f),
                                startY = 0f,
                                endY = size.height
                            )
                            onDrawBehind {
                                drawRect(sideScrim)
                                drawRect(bottomScrim)
                            }
                        }
                )
                NetflixBillboardInfo(
                    item = item,
                    logoUrl = logoUrl,
                    isFocused = isFocused,
                    focusedButton = focusedButton,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .fillMaxWidth(0.58f)
                        .padding(start = 36.dp, bottom = 30.dp)
                )
            }
        }
    }
}

private val NetflixTextShadow = Shadow(
    color = Color.Black.copy(alpha = 0.85f),
    offset = Offset(0f, 2f),
    blurRadius = 6f
)

@Composable
private fun NetflixBillboardInfo(
    item: MediaItem,
    logoUrl: String?,
    isFocused: Boolean,
    focusedButton: Int,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!logoUrl.isNullOrBlank()) {
            AsyncImage(
                model = logoUrl,
                contentDescription = item.title,
                contentScale = ContentScale.Fit,
                alignment = Alignment.BottomStart,
                modifier = Modifier
                    .height(88.dp)
                    .widthIn(max = 340.dp)
                    .fillMaxWidth()
            )
        } else {
            Text(
                text = item.title,
                style = ArflixTypography.heroTitle.copy(
                    fontSize = 36.sp,
                    fontWeight = FontWeight.Black,
                    shadow = NetflixTextShadow
                ),
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        NetflixMetaLine(item = item, fontSize = 15)
        val overview = remember(item.overview, context) { context.cleanOverviewText(item.overview) }
        Text(
            text = overview,
            style = ArflixTypography.body.copy(
                fontSize = 15.sp,
                lineHeight = 21.sp,
                shadow = NetflixTextShadow
            ),
            color = Color.White,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(4.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            // With focus elsewhere (the top bar), Play keeps the resting highlight.
            NetflixBillboardButton(
                label = stringResource(R.string.play),
                icon = { tint ->
                    Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
                },
                highlighted = if (isFocused) focusedButton == 0 else true
            )
            NetflixBillboardButton(
                label = stringResource(R.string.home_more_info),
                icon = { tint ->
                    Icon(Icons.Filled.Info, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
                },
                highlighted = isFocused && focusedButton == 1
            )
        }
    }
}

@Composable
private fun NetflixBillboardButton(
    label: String,
    icon: @Composable (Color) -> Unit,
    highlighted: Boolean
) {
    val content = if (highlighted) Color.Black else Color.White
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (highlighted) Color.White else Color.White.copy(alpha = 0.22f))
            .padding(horizontal = 22.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        icon(content)
        Text(
            text = label,
            style = ArflixTypography.label.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold),
            color = content,
            maxLines = 1
        )
    }
}

/** "Series • Drama • 2026 • 16+": the Netflix metadata line. */
@Composable
private fun NetflixMetaLine(item: MediaItem, fontSize: Int) {
    val context = LocalContext.current
    val parts = remember(item.id, item.mediaType, item.genreIds, item.year, item.duration, item.contentRating, context) {
        buildList {
            add(context.getString(if (item.mediaType == MediaType.TV) R.string.series else R.string.movie))
            context.genreNames(item.mediaType, item.genreIds).firstOrNull()?.let(::add)
            item.year.takeIf { it.isNotBlank() }?.let(::add)
            item.duration.takeIf { it.isNotBlank() && it != "0m" }?.let(::add)
            item.contentRating?.takeIf { it.isNotBlank() }?.let(::add)
        }
    }
    Text(
        text = parts.joinToString("  •  "),
        style = ArflixTypography.caption.copy(
            fontSize = fontSize.sp,
            fontWeight = FontWeight.Bold,
            shadow = NetflixTextShadow
        ),
        color = Color.White.copy(alpha = 0.92f),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

/**
 * A Netflix row. In the focused row the focused title is a wide backdrop card with its
 * description below, and the other titles are posters of the same height. Other rows
 * keep the regular card size.
 */
@Composable
private fun NetflixContentRow(
    category: Category,
    cardLogoUrls: Map<String, String>,
    isCurrentRow: Boolean,
    focusedItemIndex: Int,
    restingItemIndex: Int,
    usePosterCards: Boolean,
    bigCardHeight: Dp,
    startPadding: Dp,
    categoryHasMore: Boolean,
    showViewAll: Boolean,
    featuredItem: MediaItem?,
    featuredOverview: String?,
    onChannelCardPlaced: (LayoutCoordinates) -> Unit,
    trailerKey: String?,
    trailerDelayMs: Long,
    trailerVolume: Float,
    onLoadMore: () -> Unit,
    onViewAll: () -> Unit,
    onItemClick: (MediaItem) -> Unit
) {
    val isContinueWatching = category.id == "continue_watching"
    val isRanked = category.title.contains("Top 10", ignoreCase = true)
    val rowState = rememberLazyListState()
    val items = remember(category.items) {
        if (category.items.isEmpty()) {
            (1..8).map { MediaItem(id = -it, title = "", mediaType = MediaType.MOVIE, isPlaceholder = true) }
        } else {
            navigableHomeItems(category.items)
        }
    }
    val itemKeys = remember(category.id, items) { stableHomeRowItemKeys(category.id, items) }
    val hasViewAllCard = showViewAll && items.none { it.isPlaceholder }
    val bigCardWidth = bigCardHeight * (16f / 9f)
    val focusedPosterWidth = bigCardHeight * (2f / 3f)
    val restingPoster = category.isPortrait(usePosterCards)
    val restingWidth = if (restingPoster) HOME_TV_POSTER_CARD_WIDTH_DP.dp else HOME_TV_LANDSCAPE_CARD_WIDTH_DP.dp
    val focusedItem = items.getOrNull(focusedItemIndex)?.takeIf { isCurrentRow && !it.isPlaceholder }

    // The focused title always sits in the first slot; a resting row keeps its position.
    val anchorIndex = (if (isCurrentRow) focusedItemIndex else restingItemIndex)
        .coerceIn(0, (items.size - 1 + if (hasViewAllCard) 1 else 0).coerceAtLeast(0))
    var lastAnchor by remember { mutableIntStateOf(-1) }
    LaunchedEffect(anchorIndex, isCurrentRow) {
        if (isCurrentRow && lastAnchor >= 0 && abs(anchorIndex - lastAnchor) <= 3) {
            rowState.animateScrollToItem(anchorIndex)
        } else {
            rowState.scrollToItem(anchorIndex)
        }
        lastAnchor = anchorIndex
    }
    val latestOnItemClick by rememberUpdatedState(onItemClick)

    Column(modifier = Modifier.padding(bottom = if (isCurrentRow) 20.dp else 10.dp)) {
        Text(
            text = localizedCategoryTitle(category),
            style = ArflixTypography.sectionTitle.copy(
                fontSize = if (isCurrentRow) 20.sp else 17.sp,
                fontWeight = FontWeight.Bold,
                shadow = NetflixTextShadow
            ),
            color = Color.White,
            modifier = Modifier.padding(start = startPadding, bottom = 8.dp)
        )
        LazyRow(
            state = rowState,
            userScrollEnabled = false,
            contentPadding = PaddingValues(start = startPadding, end = bigCardWidth),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            itemsIndexed(
                items = items,
                key = { index, _ -> itemKeys[index] },
                contentType = { index, item ->
                    when {
                        item.isPlaceholder -> "placeholder_card"
                        isCurrentRow && index == focusedItemIndex -> "netflix_featured_card"
                        isCurrentRow -> "netflix_poster_card"
                        else -> "netflix_resting_card"
                    }
                }
            ) { index, item ->
                if (!item.isPlaceholder && categoryHasMore && index >= items.size - 5) {
                    LaunchedEffect(items.size) { onLoadMore() }
                }
                val onClick = remember(item) { { latestOnItemClick(item) } }
                // The rank ribbon would cover the card's trailer, so it hides while one plays.
                var cardTrailerPlaying by remember(itemKeys[index]) { mutableStateOf(false) }
                Box {
                    when {
                        isCurrentRow && index == focusedItemIndex && !item.isPlaceholder -> NetflixFeaturedCard(
                            item = item,
                            logoUrl = cardLogoUrls["${item.mediaType}_${item.id}"],
                            width = bigCardWidth,
                            height = bigCardHeight,
                            showProgress = isContinueWatching,
                            trailerKey = trailerKey,
                            trailerDelayMs = trailerDelayMs,
                            trailerVolume = trailerVolume,
                            onTrailerPlaying = { cardTrailerPlaying = it },
                            onChannelCardPlaced = onChannelCardPlaced
                        )
                        isCurrentRow -> MediaCard(
                            item = item,
                            width = focusedPosterWidth,
                            isLandscape = false,
                            showLogoImage = false,
                            raiseOnFocus = false,
                            showProgress = isContinueWatching,
                            showTitle = false,
                            focusedScale = 1f,
                            animateFocus = false,
                            enableSystemFocus = false,
                            onClick = onClick
                        )
                        else -> MediaCard(
                            item = item,
                            width = restingWidth,
                            isLandscape = !restingPoster,
                            logoImageUrl = cardLogoUrls["${item.mediaType}_${item.id}"],
                            showLogoImage = true,
                            raiseOnFocus = false,
                            showProgress = isContinueWatching,
                            showTitle = false,
                            focusedScale = 1f,
                            animateFocus = false,
                            enableSystemFocus = false,
                            onClick = onClick
                        )
                    }
                    val trailerCovering = cardTrailerPlaying && isCurrentRow && index == focusedItemIndex
                    if (isRanked && index < 10 && !item.isPlaceholder && !trailerCovering) {
                        TopRankRibbon(
                            rank = index + 1,
                            isFocused = isCurrentRow && index == focusedItemIndex,
                            compact = !isCurrentRow && !restingPoster,
                            modifier = Modifier
                                .align(Alignment.TopStart)
                                .padding(start = 8.dp)
                        )
                    }
                }
            }
            if (hasViewAllCard) {
                item(key = "${category.id}_view_all", contentType = "view_all_card") {
                    HomeViewAllCard(
                        width = if (isCurrentRow) focusedPosterWidth else restingWidth,
                        isLandscape = !isCurrentRow && !restingPoster,
                        isFocused = isCurrentRow && focusedItemIndex == items.size,
                        enableSystemFocus = false,
                        onClick = onViewAll
                    )
                }
            }
        }
        if (focusedItem != null) {
            // The ViewModel hero carries the loaded details once it is this title.
            val isFeatured = featuredItem.isSameHomeHero(focusedItem)
            val details = featuredItem?.takeIf { isFeatured } ?: focusedItem
            NetflixCardDescription(
                item = details,
                overviewOverride = featuredOverview?.takeIf { isFeatured },
                // Spans the big card and the next poster, as Netflix does, so the
                // overview is not cut at the card edge.
                modifier = Modifier
                    .padding(start = startPadding + 4.dp, end = startPadding, top = 10.dp)
                    .widthIn(max = bigCardWidth + focusedPosterWidth + 12.dp)
                    .fillMaxWidth()
            )
        }
    }
}

@Composable
private fun NetflixCardDescription(
    item: MediaItem,
    overviewOverride: String?,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val overview = remember(overviewOverride, item.overview, context) {
        context.cleanOverviewText(overviewOverride ?: item.overview)
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (item.isIptvChannel()) NetflixLiveLine(item) else NetflixMetaLine(item = item, fontSize = 13)
        Text(
            text = overview,
            style = ArflixTypography.body.copy(fontSize = 14.sp, lineHeight = 19.sp),
            color = Color.White.copy(alpha = 0.9f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun NetflixFeaturedCard(
    item: MediaItem,
    logoUrl: String?,
    width: Dp,
    height: Dp,
    showProgress: Boolean,
    trailerKey: String?,
    trailerDelayMs: Long,
    trailerVolume: Float,
    onTrailerPlaying: (Boolean) -> Unit = {},
    onChannelCardPlaced: (LayoutCoordinates) -> Unit = {}
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    if (item.isIptvChannel()) {
        NetflixChannelCard(item, width, height, onChannelCardPlaced)
        return
    }
    val focusedAtMs = remember(item.id, item.mediaType) { SystemClock.elapsedRealtime() }
    val imageRequest = remember(item.backdrop, item.image, width, height) {
        (item.backdrop ?: item.image).takeIf { it.isNotBlank() }?.let { url ->
            val widthPx = with(density) { width.roundToPx() }.coerceAtLeast(1)
            val heightPx = with(density) { height.roundToPx() }.coerceAtLeast(1)
            ImageRequest.Builder(context)
                .data(TmdbImageSizing.forSlot(url, widthPx, heightPx, TmdbImageSizing.Kind.BACKDROP))
                .size(widthPx, heightPx)
                .precision(Precision.INEXACT)
                .build()
        }
    }
    Box(
        modifier = Modifier
            .width(width)
            .height(height)
            .border(2.5.dp, Color.White, RoundedCornerShape(10.dp))
            // Keeps the focus outline off the trailer.
            .padding(4.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(Color.Black)
            .testTag("netflix_card_${item.mediaType}_${item.id}")
    ) {
        HomeTrailerPreview(
            youtubeKey = trailerKey,
            delayMs = trailerDelayMs,
            autoplayNotBeforeMs = focusedAtMs + trailerDelayMs.coerceAtLeast(500L),
            volume = trailerVolume,
            onStateChange = { state -> onTrailerPlaying(state.coversTrailer()) },
            modifier = Modifier.fillMaxSize()
        ) {
            Box(Modifier.fillMaxSize()) {
                if (imageRequest != null) {
                    AsyncImage(
                        model = imageRequest,
                        contentDescription = item.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0.5f to Color.Transparent,
                                1f to Color.Black.copy(alpha = 0.65f)
                            )
                        )
                )
                if (!logoUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = logoUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        alignment = Alignment.BottomStart,
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 16.dp, bottom = if (showProgress) 22.dp else 16.dp)
                            .fillMaxWidth(0.45f)
                            .height(64.dp)
                    )
                } else {
                    Text(
                        text = item.title,
                        style = ArflixTypography.sectionTitle.copy(
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Black,
                            shadow = NetflixTextShadow
                        ),
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 16.dp, bottom = 16.dp)
                            .fillMaxWidth(0.6f)
                    )
                }
                if (showProgress && item.progress > 0) {
                    Box(
                        Modifier
                            .align(Alignment.BottomStart)
                            .fillMaxWidth()
                            .height(4.dp)
                            .background(Color.White.copy(alpha = 0.25f))
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth(item.progress.coerceIn(0, 100) / 100f)
                                .fillMaxHeight()
                                .background(Color(0xFFE50914))
                        )
                    }
                }
            }
        }
    }
}

private fun MediaItem.isIptvChannel(): Boolean = status?.startsWith("iptv:") == true

/** "LIVE  Channel • Group": the channel's metadata line. */
@Composable
private fun NetflixLiveLine(item: MediaItem) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.live).uppercase(),
            style = ArflixTypography.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Black),
            color = Color.White,
            modifier = Modifier
                .background(Color(0xFFE50914), RoundedCornerShape(4.dp))
                .padding(horizontal = 8.dp, vertical = 2.dp)
        )
        Text(
            text = listOf(item.title, item.subtitle).filter { it.isNotBlank() }.distinct().joinToString("  •  "),
            style = ArflixTypography.caption.copy(fontSize = 13.sp, fontWeight = FontWeight.Bold),
            color = Color.White.copy(alpha = 0.92f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** The focused channel's card: border and logo. Its live preview is [NetflixChannelPreview]. */
@Composable
private fun NetflixChannelCard(
    item: MediaItem,
    width: Dp,
    height: Dp,
    onMediaPlaced: (LayoutCoordinates) -> Unit
) {
    Box(
        modifier = Modifier
            .width(width)
            .height(height)
            .border(2.5.dp, Color.White, RoundedCornerShape(10.dp))
            .padding(4.dp)
            .onGloballyPositioned(onMediaPlaced)
            .clip(RoundedCornerShape(7.dp))
            .testTag("netflix_channel_${item.id}")
    ) {
        NetflixChannelLogo(item)
    }
}

@Composable
private fun NetflixChannelLogo(item: MediaItem) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF15161A)),
        contentAlignment = Alignment.Center
    ) {
        if (item.image.isNotBlank()) {
            AsyncImage(
                model = item.image,
                contentDescription = item.title,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth(0.4f)
                    .fillMaxHeight(0.5f)
            )
        } else {
            Text(
                text = item.title,
                style = ArflixTypography.sectionTitle.copy(fontSize = 24.sp, fontWeight = FontWeight.Black),
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/**
 * The live preview over the focused channel card. The logo covers the surface until the
 * focused channel's own stream renders, so the previous channel's last frame never shows
 * on the new card.
 */
@Composable
private fun NetflixChannelPreview(
    player: androidx.media3.exoplayer.ExoPlayer,
    focusedItem: MediaItem,
    streamItem: MediaItem?,
    modifier: Modifier = Modifier
) {
    var frameShown by remember(focusedItem.id) { mutableStateOf(false) }
    val latestFocused by rememberUpdatedState(focusedItem)
    val latestStream by rememberUpdatedState(streamItem)
    DisposableEffect(player, focusedItem.id) {
        val listener = object : androidx.media3.common.Player.Listener {
            override fun onRenderedFirstFrame() {
                if (latestStream.isSameHomeHero(latestFocused)) frameShown = true
            }

            // Returning to the channel that is still prepared resumes without a new first frame.
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying && player.videoSize.width > 0 && latestStream.isSameHomeHero(latestFocused)) {
                    frameShown = true
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    Box(modifier = modifier.clip(RoundedCornerShape(7.dp))) {
        HomeHeroVideoSurface(player = player, modifier = Modifier.fillMaxSize())
        if (!frameShown) NetflixChannelLogo(focusedItem)
    }
}

/** Whether the official player is on screen (started and not finished). */
private fun PlayerConstants.PlayerState.coversTrailer(): Boolean = when (this) {
    PlayerConstants.PlayerState.PLAYING,
    PlayerConstants.PlayerState.BUFFERING,
    PlayerConstants.PlayerState.PAUSED -> true
    else -> false
}
