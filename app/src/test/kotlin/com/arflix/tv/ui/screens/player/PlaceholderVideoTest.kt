package com.arflix.tv.ui.screens.player

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaceholderVideoTest {
    private val gb = 1024L * 1024 * 1024

    @Test
    fun `a two minute clip in place of a large file is a placeholder`() {
        assertTrue(isLikelyPlaceholderVideo(durationMs = 120_000L, promisedSizeBytes = 4 * gb))
    }

    @Test
    fun `real content is not a placeholder`() {
        assertFalse(isLikelyPlaceholderVideo(durationMs = 42 * 60_000L, promisedSizeBytes = 2 * gb))
        // A short file that never claimed to be big, e.g. a trailer or a sample.
        assertFalse(isLikelyPlaceholderVideo(durationMs = 120_000L, promisedSizeBytes = 80L * 1024 * 1024))
        // Size unknown: nothing to compare against.
        assertFalse(isLikelyPlaceholderVideo(durationMs = 120_000L, promisedSizeBytes = 0L))
        assertFalse(isLikelyPlaceholderVideo(durationMs = 0L, promisedSizeBytes = 4 * gb))
    }
}
