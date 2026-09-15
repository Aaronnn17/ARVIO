package com.arflix.tv.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Touch reordering for a [androidx.compose.foundation.lazy.LazyColumn]: press and hold any row,
 * then drag it. The held row floats above the list while the others make room for it.
 *
 * Three properties make this different from the hand-rolled drag handles elsewhere in the app
 * (playlists, portals, catalogs), and they are the reason this lives in its own file:
 *
 *  1. **The gesture is keyed to the row's key, never to its position.** A row that moves while the
 *     finger is still down keeps the same key, so the gesture survives every step. Keying on the
 *     index cancels the gesture after the first move, which limits the user to one position per
 *     press.
 *  2. **No row height is ever assumed.** Every position is read from [LazyListState.layoutInfo],
 *     so rows of different heights, and rows that change height, stay under the finger.
 *  3. **The list scrolls itself** while a row is held against the top or bottom edge, which is what
 *     makes lists longer than one screen reorderable at all.
 *
 * The held row is drawn at the position the finger put it, expressed in the list's own viewport
 * coordinates. Its translation is recomputed from the live layout on every frame rather than
 * accumulated, so the row never jumps when the underlying order arrives a frame or two late -
 * which it does here, because the order is persisted before it comes back through the UI state.
 *
 * Usage:
 * ```
 * val listState = rememberLazyListState()
 * val reorderState = rememberDragReorderState(listState) { key, from, to -> /* move one step */ }
 * LazyColumn(state = listState, userScrollEnabled = reorderState.draggedKey == null) {
 *     items(rows, key = { it.id }) { row ->
 *         Row(modifier = dragReorderItem(reorderState, row.id)) { /* ... */ }
 *     }
 * }
 * ```
 * While a row is held the list is taken off the finger (`userScrollEnabled`): it still scrolls, but
 * only by itself, at the edges, which is the only scrolling that belongs to a move.
 *
 * ⚠️ The list must not use a top `contentPadding`: row offsets and the finger position are compared
 * in the same coordinate space, and top padding shifts the two apart.
 */
@Stable
class DragReorderState internal constructor(
    private val listState: LazyListState,
    private val scope: CoroutineScope,
    private val autoScrollEdgePx: Float,
    private val autoScrollSpeedPx: Float,
    private val onGrab: () -> Unit,
    private val onMove: (key: Any, from: Int, to: Int) -> Unit
) {
    /** The key of the row currently held, or null while nothing is held. */
    var draggedKey by mutableStateOf<Any?>(null)
        private set

    /** Set when a row was picked up and put down again without being moved. */
    private var pickedUpWithoutMoving = false
    private var movedWhileHeld = false

    /** Top edge of the held row in viewport coordinates - where the finger put it. */
    private var floatingTop = 0f
    private var floatingSize = 0
    /** Finger position in viewport coordinates, which is what the edge scrolling watches. */
    private var pointerY = 0f
    /** The position this row has been asked to end up at, including moves not yet echoed back. */
    private var requestedIndex = -1
    private var autoScrollJob: Job? = null

    fun isDragging(key: Any): Boolean = draggedKey == key

    /**
     * Whether the tap that is arriving right now is only the release of a row that was picked up,
     * and should therefore do nothing. Answers once and forgets, so the next real tap counts.
     *
     * 🔴 **A row cannot simply be given a long-press handler of its own instead.** A long-press
     * handler swallows every finger movement that follows it, which is precisely the movement the
     * move needs - the row would light up and then sit still. So the pick-up is detected in one
     * place only, here, and the tap asks afterwards whether it still means anything.
     */
    fun consumeClickAfterPickUp(): Boolean {
        val suppress = pickedUpWithoutMoving
        pickedUpWithoutMoving = false
        return suppress
    }

    /**
     * How far the held row has to be shifted from where the list laid it out to sit where the
     * finger put it. Read live during drawing, so a late-arriving order correction is absorbed
     * instead of showing up as a jump.
     */
    internal fun translationFor(key: Any): Float {
        val item = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == key } ?: return 0f
        return floatingTop - item.offset
    }

    internal fun onDragStart(key: Any, positionInRow: Float) {
        val grabbed = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == key } ?: return
        draggedKey = key
        floatingTop = grabbed.offset.toFloat()
        floatingSize = grabbed.size
        // The finger position is kept in the list's coordinates, because that is
        // what the edge scrolling below compares against the viewport.
        pointerY = grabbed.offset + positionInRow
        requestedIndex = grabbed.index
        movedWhileHeld = false
        pickedUpWithoutMoving = false
        onGrab()
        startAutoScroll()
    }

    internal fun onDrag(deltaY: Float) {
        if (draggedKey == null) return
        movedWhileHeld = true
        floatingTop += deltaY
        pointerY += deltaY
        applyMoves()
    }

    internal fun onDragStop() {
        autoScrollJob?.cancel()
        autoScrollJob = null
        // A row that was picked up and never moved is released like an ordinary tap, and the tap
        // would show or hide the group - which is not what changing one's mind should do. A row
        // that WAS moved never reaches the tap: the movement is claimed by the move itself.
        pickedUpWithoutMoving = draggedKey != null && !movedWhileHeld
        movedWhileHeld = false
        draggedKey = null
        requestedIndex = -1
    }

    /**
     * Moves the held row one step at a time until it sits where the finger is. Steps are counted
     * against [requestedIndex] rather than against the rendered position, so a step that has been
     * asked for but has not come back through the UI state yet is never asked for twice.
     */
    private fun applyMoves() {
        val key = draggedKey ?: return
        val layout = listState.layoutInfo
        val slots = layout.visibleItemsInfo.map { ReorderSlot(it.index, it.offset, it.size) }
        val target = reorderTargetIndex(slots, floatingTop + floatingSize / 2f, layout.totalItemsCount) ?: return
        if (target == requestedIndex) return
        val step = if (target > requestedIndex) 1 else -1
        while (requestedIndex != target) {
            onMove(key, requestedIndex, requestedIndex + step)
            requestedIndex += step
        }
    }

    /** Keeps the list moving for as long as the held row rests against the top or bottom edge. */
    private fun startAutoScroll() {
        autoScrollJob?.cancel()
        autoScrollJob = scope.launch {
            while (isActive && draggedKey != null) {
                withFrameNanos { }
                val layout = listState.layoutInfo
                val delta = autoScrollDelta(
                    pointerY = pointerY,
                    viewportStart = layout.viewportStartOffset.toFloat(),
                    viewportEnd = layout.viewportEndOffset.toFloat(),
                    edgeSize = autoScrollEdgePx,
                    maxSpeed = autoScrollSpeedPx
                )
                if (delta != 0f) {
                    listState.scrollBy(delta)
                    applyMoves()
                }
            }
        }
    }
}

/**
 * Remembers the state that [Modifier.dragReorderable] and [dragReorderItem] share.
 *
 * [onMove] is called once per position the row passes, with the row's key and the two positions.
 * Callers that address their rows by name - as they should, see property 1 above - can use the key
 * and ignore the indices.
 */
@Composable
fun rememberDragReorderState(
    listState: LazyListState,
    onMove: (key: Any, from: Int, to: Int) -> Unit
): DragReorderState {
    val scope = rememberCoroutineScope()
    val haptics: HapticFeedback = LocalHapticFeedback.current
    val currentOnMove by rememberUpdatedState(onMove)
    val density = LocalDensity.current
    val edgePx = with(density) { autoScrollEdge.toPx() }
    val speedPx = with(density) { autoScrollSpeedPerFrame.toPx() }
    return remember(listState, scope, edgePx, speedPx) {
        DragReorderState(
            listState = listState,
            scope = scope,
            autoScrollEdgePx = edgePx,
            autoScrollSpeedPx = speedPx,
            onGrab = { haptics.performHapticFeedback(HapticFeedbackType.LongPress) },
            onMove = { key, from, to -> currentOnMove(key, from, to) }
        )
    }
}

/**
 * Put on every row, and it does both halves: it takes the press and hold that picks the row up and
 * the drag that moves it, and it lifts the held row above the list while the others slide out of
 * its way. The sliding is [Modifier.animateItemPlacement], which needs nothing but stable keys.
 *
 * Called from inside the item itself - `modifier = dragReorderItem(state, key)`.
 *
 * 🔴 **The gesture belongs on the row, not on the list.** A list scrolls its own content, and it
 * sees a drag before anything wrapped around it does; a detector sitting outside the list is handed
 * a gesture the list has already taken for scrolling, so the row lights up when it is picked up and
 * then refuses to move. Inside the row the drag is claimed first, and the list never sees it.
 *
 * The gesture is kept at the FRONT of the modifier chain and keyed by the row's key, so that
 * picking a row up - which changes everything behind it in the chain - cannot restart the very
 * gesture that is running.
 */
@OptIn(ExperimentalFoundationApi::class)
fun LazyItemScope.dragReorderItem(state: DragReorderState, key: Any): Modifier = Modifier
    .pointerInput(key) {
        detectDragGesturesAfterLongPress(
            onDragStart = { offset -> state.onDragStart(key, offset.y) },
            onDrag = { change, amount ->
                change.consume()
                state.onDrag(amount.y)
            },
            onDragEnd = { state.onDragStop() },
            onDragCancel = { state.onDragStop() }
        )
    }
    .then(
        if (state.isDragging(key)) {
            Modifier
                .zIndex(1f)
                .graphicsLayer {
                    translationY = state.translationFor(key)
                    scaleX = DRAGGED_SCALE
                    scaleY = DRAGGED_SCALE
                    shadowElevation = draggedElevation.toPx()
                    shape = RoundedCornerShape(draggedCorner)
                    clip = false
                }
        } else {
            Modifier.animateItemPlacement()
        }
    )

// ---------------------------------------------------------------------------
// The arithmetic, kept free of Compose so it can be tested on its own.
// ---------------------------------------------------------------------------

/** One row as the list laid it out: where it starts and how tall it actually is. */
internal data class ReorderSlot(val index: Int, val offset: Int, val size: Int)

/**
 * The position the held row belongs at: the row whose slot its middle currently sits in.
 * Past either end of what is on screen it sticks to the outermost visible row, which is where
 * edge scrolling takes over. Returns null when there is nothing to reorder.
 */
internal fun reorderTargetIndex(slots: List<ReorderSlot>, floatingCenter: Float, itemCount: Int): Int? {
    if (slots.isEmpty() || itemCount <= 0) return null
    val hit = slots.firstOrNull { floatingCenter >= it.offset && floatingCenter < it.offset + it.size }
    val index = when {
        hit != null -> hit.index
        floatingCenter < slots.first().offset -> slots.first().index
        else -> slots.last().index
    }
    return index.coerceIn(0, itemCount - 1)
}

/**
 * How far to scroll this frame while a row is held near an edge: negative towards the start of the
 * list, positive towards its end, zero anywhere in the middle. The speed ramps up with how deep
 * into the edge strip the finger is, so resting just inside it creeps and pushing right up against
 * the edge runs at [maxSpeed]. When the viewport is too short for two strips the top one wins.
 */
internal fun autoScrollDelta(
    pointerY: Float,
    viewportStart: Float,
    viewportEnd: Float,
    edgeSize: Float,
    maxSpeed: Float
): Float {
    if (edgeSize <= 0f || viewportEnd <= viewportStart) return 0f
    val topEdge = viewportStart + edgeSize
    val bottomEdge = viewportEnd - edgeSize
    return when {
        pointerY < topEdge -> -maxSpeed * ((topEdge - pointerY) / edgeSize).coerceIn(0f, 1f)
        pointerY > bottomEdge -> maxSpeed * ((pointerY - bottomEdge) / edgeSize).coerceIn(0f, 1f)
        else -> 0f
    }
}

private val autoScrollEdge = 72.dp
private val autoScrollSpeedPerFrame = 8.dp
private val draggedElevation = 12.dp
private val draggedCorner = 12.dp
private const val DRAGGED_SCALE = 1.03f
