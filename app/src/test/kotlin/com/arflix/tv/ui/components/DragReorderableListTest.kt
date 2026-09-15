package com.arflix.tv.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two calculations behind press-and-hold reordering. Rows here are deliberately NOT all the
 * same height: the point of reading the real layout is that nothing breaks when they differ.
 */
class DragReorderableListTest {

    private val evenRows = listOf(
        ReorderSlot(index = 0, offset = 0, size = 100),
        ReorderSlot(index = 1, offset = 100, size = 100),
        ReorderSlot(index = 2, offset = 200, size = 100),
        ReorderSlot(index = 3, offset = 300, size = 100)
    )

    @Test
    fun rowStaysPutWhileItsMiddleIsStillInsideItsOwnSlot() {
        assertEquals(1, reorderTargetIndex(evenRows, floatingCenter = 149f, itemCount = 4))
    }

    @Test
    fun rowTakesTheSlotItsMiddleHasMovedInto() {
        assertEquals(2, reorderTargetIndex(evenRows, floatingCenter = 250f, itemCount = 4))
    }

    @Test
    fun rowsOfDifferentHeightsAreReadFromTheLayoutNotAssumed() {
        val unevenRows = listOf(
            ReorderSlot(index = 0, offset = 0, size = 40),
            ReorderSlot(index = 1, offset = 40, size = 160),
            ReorderSlot(index = 2, offset = 200, size = 60)
        )
        assertEquals(1, reorderTargetIndex(unevenRows, floatingCenter = 190f, itemCount = 3))
        assertEquals(2, reorderTargetIndex(unevenRows, floatingCenter = 210f, itemCount = 3))
    }

    @Test
    fun draggingAboveTheFirstRowStopsAtTheFirstRow() {
        assertEquals(0, reorderTargetIndex(evenRows, floatingCenter = -500f, itemCount = 4))
    }

    @Test
    fun draggingBelowTheLastRowStopsAtTheLastRow() {
        assertEquals(3, reorderTargetIndex(evenRows, floatingCenter = 5000f, itemCount = 4))
    }

    @Test
    fun aRowScrolledOutOfSightNeverBecomesATargetBeyondTheList() {
        // Only rows 40..43 are on screen; the answer stays inside the list either way.
        val scrolled = listOf(
            ReorderSlot(index = 40, offset = 0, size = 100),
            ReorderSlot(index = 41, offset = 100, size = 100)
        )
        assertEquals(41, reorderTargetIndex(scrolled, floatingCenter = 9000f, itemCount = 44))
        assertEquals(40, reorderTargetIndex(scrolled, floatingCenter = -9000f, itemCount = 44))
    }

    @Test
    fun emptyListHasNothingToReorder() {
        assertNull(reorderTargetIndex(emptyList(), floatingCenter = 0f, itemCount = 0))
        assertNull(reorderTargetIndex(evenRows, floatingCenter = 0f, itemCount = 0))
    }

    @Test
    fun theHeldRowStaysInsideTheListWhenTheFingerLeavesIt() {
        // Finger above the list, finger below it, finger inside it.
        assertEquals(0f, clampFloatingTop(-800f, viewportStart = 0, viewportEnd = 1000, rowSize = 100), 0f)
        assertEquals(900f, clampFloatingTop(5000f, viewportStart = 0, viewportEnd = 1000, rowSize = 100), 0f)
        assertEquals(420f, clampFloatingTop(420f, viewportStart = 0, viewportEnd = 1000, rowSize = 100), 0f)
    }

    @Test
    fun aRowTallerThanTheViewportIsPinnedToTheTopInsteadOfAbsurdity() {
        assertEquals(0f, clampFloatingTop(50f, viewportStart = 0, viewportEnd = 80, rowSize = 400), 0f)
    }

    @Test
    fun theMiddleOfTheListDoesNotScroll() {
        val delta = autoScrollDelta(pointerY = 500f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        assertEquals(0f, delta, 0f)
    }

    @Test
    fun holdingAtTheTopEdgeScrollsBackwards() {
        val delta = autoScrollDelta(pointerY = 50f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        assertEquals(-4f, delta, 0.001f)
    }

    @Test
    fun holdingAtTheBottomEdgeScrollsForwards() {
        val delta = autoScrollDelta(pointerY = 950f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        assertEquals(4f, delta, 0.001f)
    }

    @Test
    fun theDeeperIntoTheEdgeTheFasterItRunsUpToTheLimit() {
        val shallow = autoScrollDelta(pointerY = 990f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        val deep = autoScrollDelta(pointerY = 1000f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        val pastTheEdge = autoScrollDelta(pointerY = 1400f, viewportStart = 0f, viewportEnd = 1000f, edgeSize = 100f, maxSpeed = 8f)
        assertTrue(shallow < deep)
        assertEquals(8f, deep, 0.001f)
        assertEquals(8f, pastTheEdge, 0.001f)
    }

    @Test
    fun aViewportWithoutHeightNeverScrolls() {
        assertEquals(0f, autoScrollDelta(10f, 0f, 0f, 100f, 8f), 0f)
        assertEquals(0f, autoScrollDelta(10f, 0f, 1000f, 0f, 8f), 0f)
    }
}
