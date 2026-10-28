package com.arflix.tv.ui.screens.player.preview

import org.junit.Assert.*
import org.junit.Test

class SeekPreviewCoverageTest {
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
