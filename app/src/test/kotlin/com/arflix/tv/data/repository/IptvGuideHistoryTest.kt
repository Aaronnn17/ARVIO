package com.arflix.tv.data.repository

import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvGuideHistory
import com.arflix.tv.data.model.IptvNowNext
import com.arflix.tv.data.model.IptvProgram
import org.junit.Assert.*
import org.junit.Test

class IptvGuideHistoryTest {
    private val channel = IptvChannel("one:1", "News", "https://example.invalid/live/one.ts", "News", catchupDays = 3)
    private val now = 1_800_000_000_000L

    @Test
    fun historyUsesAdvertisedProviderWindowWithBoundedFallback() {
        assertEquals(3, IptvGuideHistory.days(channel))
        assertEquals(1, IptvGuideHistory.days(channel.copy(catchupDays = 1)))
        assertEquals(7, IptvGuideHistory.days(channel.copy(catchupDays = 30)))
        assertEquals(3, IptvGuideHistory.days(channel.copy(catchupDays = 0)))
    }

    @Test
    fun manyShortProgrammesDoNotMasqueradeAsFullHistory() {
        val short = IptvNowNext(recent = List(24) { i -> IptvProgram("Show $i",
            startUtcMillis = now - (24 - i) * 5 * 60_000L, endUtcMillis = now - (23 - i) * 5 * 60_000L) })
        assertFalse(IptvGuideHistory.hasCoverage(short, 3 * IptvGuideHistory.DAY_MS, now))
    }

    @Test
    fun threeDaysOfHistorySatisfiesThreeDayProviderButNotSevenDayProvider() {
        val guide = IptvNowNext(recent = listOf(IptvProgram("Older show",
            startUtcMillis = now - 3 * IptvGuideHistory.DAY_MS, endUtcMillis = now - 3 * IptvGuideHistory.DAY_MS + 60_000L)))
        assertTrue(IptvGuideHistory.hasCoverage(guide, 3 * IptvGuideHistory.DAY_MS, now))
        assertFalse(IptvGuideHistory.hasCoverage(guide, 7 * IptvGuideHistory.DAY_MS, now))
    }
}
