package com.arflix.tv.ui.screens.tv.live

import com.arflix.tv.data.model.*
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class SportsCatalogueTest {
    private val now = Instant.parse("2026-09-10T12:00:00Z").toEpochMilli()
    private val channel = IptvChannel("p:1", "UK | Sky Sports Main Event FHD", streamUrl = "https://example.invalid/live", group = "Sports")
    private val fixture = SportsFixture("42", "English Premier League", null, null, null, "scheduled", now, null, null,
        listOf(SportsBroadcaster("Sky Sports Main Event HD", "United Kingdom", now + 3600000)))
    private val art = SportsEventArtwork("North vs South", "", listOf("Soccer"), now + 3600000, source = "TheSportsDB", fixture = fixture)
    private val p = IptvProgram("North vs South", startUtcMillis = now - 60000, endUtcMillis = now + 3600000)
    private val epg = SportsGuideEvent("guide", p.title, GuideSport.FOOTBALL, p, listOf(channel), competition = "Premier League")

    @Test fun fixtureWithoutArtworkOrChannelsIsBrowsableButNeverInventsLiveStatus() {
        val event = buildSportsCatalogue(emptyList(), listOf(art), emptyList(), now).single()
        assertEquals("sportsdb:42", event.id)
        assertTrue(event.channels.isEmpty())
        assertFalse(event.isOnAir(now + 7200000))
        assertEquals("upcoming", sportsGuideRows(listOf(event), now).single().id)
    }
    @Test fun possibleBroadcastsAreSeparateAndHiddenSourcesDoNotLeak() {
        val wrong = channel.copy(id = "wrong", name = "DE | Sky Sports Main Event HD")
        val hint = buildSportsCatalogue(emptyList(), listOf(art), listOf(channel, wrong), now).single()
        assertTrue(hint.channels.isEmpty())
        assertEquals(listOf(channel.id), hint.possibleChannels.map { it.id })
        assertTrue(buildSportsCatalogue(emptyList(), listOf(art), emptyList(), now).single().possibleChannels.isEmpty())
        val actual = buildSportsCatalogue(listOf(epg), listOf(art.copy(startsAt = now)), listOf(channel), now).single()
        assertEquals(listOf(channel), actual.availableChannels(now))
        assertEquals(p.endUtcMillis, actual.schedules[channel.id]!!.endUtcMillis)
    }
    @Test fun qualifiersOtherLeaguesAndOtherTimesRemainSeparate() {
        for (changed in listOf(art.copy(fixture = fixture.copy(qualifier = "women")), art.copy(genres = listOf("Basketball")),
            art.copy(startsAt = now + 10800000), art.copy(fixture = fixture.copy(league = "UEFA Champions League")))) {
            val result = buildSportsCatalogue(listOf(epg), listOf(changed), emptyList(), now)
            assertTrue(result.single { it.fixture != null }.channels.isEmpty())
            assertEquals(1, result.count { it.fixture == null })
        }
    }
    @Test fun liveExpiresAndFinishedEventsSuppressOldGuide() {
        val live = art.copy(startsAt = now - 60000, fixture = fixture.copy(status = "live"))
        val event = buildSportsCatalogue(emptyList(), listOf(live), emptyList(), now).single()
        assertTrue(event.isConfirmedLive(now))
        assertFalse(event.isOnAir(now + 300001))
        assertTrue(buildSportsCatalogue(listOf(epg), listOf(art.copy(startsAt = now, fixture = fixture.copy(status = "finished"))), emptyList(), now).isEmpty())
    }
    @Test fun prominentLiveFirstButUpcomingStaysChronological() {
        val event = buildSportsCatalogue(emptyList(), listOf(art.copy(startsAt = now, fixture = fixture.copy(status = "live"))), emptyList(), now).single()
        val minor = event.copy(id = "minor", prominence = 0)
        assertEquals(event.id, sportsGuideRows(listOf(minor, event), now).first().events.first().id)
        val later = event.copy(id = "later", fixture = fixture, programme = p.copy(startUtcMillis = now + 7200000), schedules = emptyMap())
        val earlier = later.copy(id = "earlier", programme = p.copy(startUtcMillis = now + 3600000), prominence = 0)
        assertEquals("earlier", sportsGuideRows(listOf(later, earlier), now).first().events.first().id)
    }
}
