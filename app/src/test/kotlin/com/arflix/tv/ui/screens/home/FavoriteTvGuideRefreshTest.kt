package com.arflix.tv.ui.screens.home

import com.arflix.tv.data.model.IptvNowNext
import com.arflix.tv.data.model.IptvProgram
import org.junit.Assert.*
import org.junit.Test

class FavoriteTvGuideRefreshTest {
    private val retry = 30 * 60_000L
    private val airing = IptvNowNext(now = IptvProgram(title = "On air", startUtcMillis = 0, endUtcMillis = 1))

    @Test fun savedGuideCoveringNowNeverAsksTheNetwork() {
        val saved = mapOf("a" to airing, "b" to airing)
        assertFalse(favoriteTvGuideNeedsNetwork(setOf("a", "b"), saved, lastNetworkMs = 0, nowMs = 10, retryMs = retry))
    }

    @Test fun aChannelWithoutACurrentProgrammeAsksOnceThenWaits() {
        val saved = mapOf("a" to airing, "b" to IptvNowNext())
        assertTrue(favoriteTvGuideNeedsNetwork(setOf("a", "b"), saved, lastNetworkMs = 0, nowMs = 10, retryMs = retry))
        assertFalse(favoriteTvGuideNeedsNetwork(setOf("a", "b"), saved, lastNetworkMs = 10, nowMs = 10 + retry - 1, retryMs = retry))
        assertTrue(favoriteTvGuideNeedsNetwork(setOf("a", "b"), saved, lastNetworkMs = 10, nowMs = 10 + retry, retryMs = retry))
    }

    @Test fun noSavedGuideAtAllCountsAsMissing() {
        assertTrue(favoriteTvGuideNeedsNetwork(setOf("a"), null, lastNetworkMs = 0, nowMs = 10, retryMs = retry))
    }

    @Test fun focusRefreshIsThrottled() {
        assertTrue(favoriteTvFocusRefreshDue(lastRefreshMs = 0, nowMs = 5, intervalMs = 60_000))
        assertFalse(favoriteTvFocusRefreshDue(lastRefreshMs = 5, nowMs = 59_000, intervalMs = 60_000))
        assertTrue(favoriteTvFocusRefreshDue(lastRefreshMs = 5, nowMs = 60_005, intervalMs = 60_000))
    }
}
