package com.arflix.tv.ui.screens.player.preview

import org.junit.Assert.*
import org.junit.Test

class SeekPreviewCoverageTest {
    @Test fun `adaptive preparation finishes a nearby window before sparse coverage`() {
        val planner = SeekPreviewCoverage()
        val cached = mutableSetOf<Long>()
        repeat(5) { tick ->
            planner.next(60_000, 7_200_000, 6_000_000_000, tick.toLong(), 0, true) { it in cached }
                ?.let { cached += it }
        }
        assertEquals(setOf(40_000L, 50_000L, 60_000L, 70_000L, 80_000L), cached)
        val broad = planner.next(60_000, 7_200_000, 6_000_000_000, 6, 0, true) { it in cached }
        assertNotNull(broad)
        assertTrue(broad!! >= 120_000)
    }

    @Test fun `rewind intent changes priorities and expires instead of following old gestures forever`() {
        val planner = SeekPreviewCoverage()
        planner.noteSeek(90_000, 0)
        planner.noteSeek(60_000, 1)
        assertEquals(-1, planner.direction(2))
        assertEquals(50_000L, planner.next(60_000, 120_000, 1000, 2, 0, true) { false })
        assertEquals(1, planner.direction(60_001))
        planner.noteSeek(80_000, 60_002)
        assertEquals(1, planner.direction(60_003))
        planner.endGesture()
        planner.noteSeek(100_000, 60_004, originMs = 120_000)
        assertEquals(-1, planner.direction(60_005))
    }

    @Test fun `moving playback does not starve wider coverage`() {
        val planner = SeekPreviewCoverage()
        val cached = mutableSetOf<Long>()
        val targets = (0..19).mapNotNull { tick ->
            planner.next(tick * 3_000L, 7_200_000, 6_000_000_000, tick * 3_000L, 0) { it in cached }
                ?.also { cached += it }
        }
        assertTrue(targets.take(4).any { it >= 120_000 })
        assertTrue(targets.any { it >= 300_000 })
        assertEquals(targets.size, targets.distinct().size)
        assertTrue(targets.any { it <= 20_000 })
    }

    @Test fun `large or unknown files remain within ten minutes ahead`() {
        for (size in listOf(null, 30_000_000_000L)) {
            val planner = SeekPreviewCoverage()
            val cached = mutableSetOf<Long>()
            repeat(120) { tick ->
                planner.next(1_000_000, 9_000_000, size, tick * 3_000L, 0) { it in cached }
                    ?.let { assertTrue(it <= 1_600_000); cached += it }
            }
            assertTrue(cached.any { it > 1_300_000 })
        }
    }

    @Test fun `exhausted wide budget preserves nearby previews for long movies`() {
        val planner = SeekPreviewCoverage()
        val cached = mutableSetOf<Long>()
        repeat(8) { tick ->
            planner.next(0, 7_200_000, 1_000, tick.toLong(), PREVIEW_SPECULATIVE_BYTES) { it in cached }
                ?.let { assertTrue(it <= 40_000); cached += it }
        }
        assertTrue(cached.contains(10_000))
        assertTrue(cached.contains(40_000))
    }

    @Test fun `failures do not trap scheduler and short media never uses EOF`() {
        val planner = SeekPreviewCoverage()
        val targets = (0..9).mapNotNull { planner.next(0, 21_000, 1_000, it.toLong(), 0) { false } }
        assertEquals(targets.size, targets.distinct().size)
        assertTrue(targets.all { it in 0 until 21_000 })
        assertNull(planner.next(0, 0, 1_000, 0, 0) { false })
    }
}
