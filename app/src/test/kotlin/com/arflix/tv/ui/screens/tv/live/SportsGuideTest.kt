package com.arflix.tv.ui.screens.tv.live

import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvNowNext
import com.arflix.tv.data.model.IptvProgram
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class SportsGuideTest {
    private val now = Instant.parse("2026-09-09T18:00:00Z").toEpochMilli()
    private val a = IptvChannel("one:1", "Football 1", "Football", "https://example.invalid/a")
    private val b = a.copy(id = "two:1", streamUrl = "https://example.invalid/b")
    private fun programme(title: String = "Football: North vs South", start: Long = now - 60_000, end: Long = now + 60_000) =
        IptvProgram(title, startUtcMillis = start, endUtcMillis = end)
    private fun slice(p: IptvProgram) = IptvNowNext(now = p, next = p, upcoming = listOf(p))

    @Test fun oneEventRetainsEachProvidersChannelWithoutDuplicates() {
        val p = programme()
        val events = buildSportsGuideEvents(listOf(a, b), mapOf(a.id to slice(p), b.id to slice(p)), now)
        assertEquals(1, events.size)
        assertEquals(listOf(a.id, b.id), events.single().channels.map { it.id })
    }
    @Test fun similarTeamsAtAnotherTimeDoNotMatch() {
        val events = buildSportsGuideEvents(listOf(a, b), mapOf(a.id to slice(programme()),
            b.id to slice(programme(start = now + 60_000, end = now + 120_000))), now)
        assertEquals(2, events.size)
    }
    @Test fun hiddenChannelNotInInputCannotLeakFromGuideMap() {
        val p = programme()
        assertEquals(listOf(a.id), buildSportsGuideEvents(listOf(a), mapOf(a.id to slice(p), b.id to slice(p)), now)
            .single().channels.map { it.id })
    }
    @Test fun expiredReplaysAndInvalidIntervalsAreExcluded() {
        for (p in listOf(programme(end = now), programme(start = now + 1, end = now),
            programme("Football highlights"), programme("Football replay"), programme("Football preview"))) {
            assertTrue(buildSportsGuideEvents(listOf(a), mapOf(a.id to slice(p)), now).isEmpty())
        }
    }
    @Test fun footballCodesAndCombatSportsStaySeparate() {
        assertEquals(GuideSport.AMERICAN_FOOTBALL, GuideSport.fromText("NFL American football"))
        assertEquals(GuideSport.FOOTBALL, GuideSport.fromText("UEFA Champions League"))
        assertEquals(GuideSport.BOXING, GuideSport.fromText("Boxing"))
        assertEquals(GuideSport.MMA, GuideSport.fromText("UFC 310"))
        assertNull(GuideSport.fromText("Generic event"))
    }
    @Test fun midnightWindowUsesDeviceZoneNotUtcAndDoesNotInventLiveStatus() {
        val start = Instant.parse("2026-09-11T01:00:00Z").toEpochMilli()
        val p = programme(start = start, end = start + 60_000)
        val guide = mapOf(a.id to slice(p))
        assertTrue(buildSportsGuideEvents(listOf(a), guide, now, ZoneId.of("Europe/Amsterdam")).isEmpty())
        val la = buildSportsGuideEvents(listOf(a), guide, now, ZoneId.of("America/Los_Angeles"))
        assertEquals(1, la.size)
        assertFalse(la.single().isOnAir(now))
    }
    @Test fun topLiveRowsDoNotRepeatTheSameEvents() {
        val programmes = (0..11).map { programme("Football: Team $it vs Other") }
        val events = buildSportsGuideEvents(listOf(a), mapOf(a.id to IptvNowNext(upcoming = programmes)), now)
        val rows = sportsGuideRows(events, now)
        val featured = rows.single { it.id == "featured" }.events.map { it.id }.toSet()
        assertEquals(8, featured.size)
        assertTrue(rows.single { it.id == "more" }.events.none { it.id in featured })
        assertFalse(rows.any { it.id == "upcoming" })
    }
}
