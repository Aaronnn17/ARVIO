package com.arflix.tv.data.repository

import com.arflix.tv.data.api.StalkerApi
import com.arflix.tv.data.model.StalkerVodLink
import com.arflix.tv.data.model.isDirectStreamUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the Stalker VOD movie matching on [IptvRepository]. The matching
 * helpers are `internal` so tests can call them directly, the same convention
 * the Stalker EPG helpers already follow.
 */
class IptvRepositoryStalkerVodTest {

    private fun newRepository(): IptvRepository {
        val context = io.mockk.mockk<android.content.Context>(relaxed = true)
        val okHttpClient = io.mockk.mockk<okhttp3.OkHttpClient>(relaxed = true)
        val profileManager = io.mockk.mockk<ProfileManager>(relaxed = true)
        val invalidationBus = io.mockk.mockk<CloudSyncInvalidationBus>(relaxed = true)
        return IptvRepository(context, okHttpClient, profileManager, invalidationBus)
    }

    private fun item(
        id: String,
        name: String,
        cmd: String = "/media/$id.mpg",
        year: String? = null,
        tmdbId: String? = null
    ) = StalkerApi.StalkerVodItem(id = id, name = name, cmd = cmd, year = year, tmdbId = tmdbId)

    // ── ID matching ───────────────────────────────────────────────────────

    @Test
    fun `a portal supplied tmdb id wins over every title score`() {
        val repository = newRepository()
        val items = listOf(
            item("1", "Dune", year = "2021", tmdbId = "438631"),
            item("2", "Dune", year = "1984", tmdbId = "841")
        )

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = "dune",
            normalizedTmdb = "438631",
            inputYear = 2021
        )

        assertEquals(listOf("1"), matches.map { it.id })
    }

    @Test
    fun `an unmatched tmdb id falls through to title scoring`() {
        val repository = newRepository()
        val items = listOf(item("1", "Dune", year = "2021"))

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = "dune",
            normalizedTmdb = "438631",
            inputYear = 2021
        )

        assertEquals(listOf("1"), matches.map { it.id })
    }

    // ── Title + year fallback ─────────────────────────────────────────────

    @Test
    fun `title and year fallback prefers the matching year`() {
        val repository = newRepository()
        val items = listOf(
            item("old", "Dune", year = "1984"),
            item("new", "Dune", year = "2021")
        )

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = "dune",
            normalizedTmdb = null,
            inputYear = 2021
        )

        assertEquals(listOf("new"), matches.map { it.id })
    }

    @Test
    fun `a language prefixed portal title still matches the tmdb title`() {
        val repository = newRepository()
        val items = listOf(item("1", "DE: Der Herr der Ringe", year = "2001"))

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = IptvTitleNormalizer.normalize("Der Herr der Ringe"),
            normalizedTmdb = null,
            inputYear = 2001
        )

        assertEquals(listOf("1"), matches.map { it.id })
    }

    @Test
    fun `unrelated portal results are dropped instead of guessed`() {
        val repository = newRepository()
        val items = listOf(
            item("1", "Completely Different Show"),
            item("2", "Another Unrelated Title")
        )

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = "dune",
            normalizedTmdb = null,
            inputYear = 2021
        )

        assertTrue(matches.isEmpty())
    }

    @Test
    fun `entries without a playable cmd never become a source`() {
        val repository = newRepository()
        val items = listOf(StalkerApi.StalkerVodItem(id = "1", name = "Dune", cmd = null, year = "2021"))

        val matches = repository.matchStalkerVodItems(
            items = items,
            normalizedTitle = "dune",
            normalizedTmdb = null,
            inputYear = 2021
        )

        assertTrue(matches.isEmpty())
    }

    @Test
    fun `an empty portal answer yields no matches`() {
        val repository = newRepository()

        assertTrue(
            repository.matchStalkerVodItems(
                items = emptyList(),
                normalizedTitle = "dune",
                normalizedTmdb = "438631",
                inputYear = 2021
            ).isEmpty()
        )
    }

    // ── Query planning ────────────────────────────────────────────────────

    @Test
    fun `a subtitled title gets one extra fallback query`() {
        val repository = newRepository()

        assertEquals(
            listOf("Dune: Part Two", "Dune"),
            repository.stalkerVodSearchQueries("Dune: Part Two")
        )
        assertEquals(
            listOf("Mission: Impossible - Dead Reckoning", "Mission"),
            repository.stalkerVodSearchQueries("Mission: Impossible - Dead Reckoning")
        )
    }

    @Test
    fun `a plain title stays a single query`() {
        val repository = newRepository()

        assertEquals(listOf("Heat"), repository.stalkerVodSearchQueries("Heat"))
        assertTrue(repository.stalkerVodSearchQueries("   ").isEmpty())
    }

    @Test
    fun `a too short head is not used as a fallback query`() {
        val repository = newRepository()

        assertEquals(listOf("It: Chapter Two"), repository.stalkerVodSearchQueries("It: Chapter Two"))
    }

    // ── Portal isolation (C1) ─────────────────────────────────────────────

    @Test
    fun `two portals sharing an internal id produce different playback markers`() {
        val first = StalkerVodLink.buildMarker("stalker1", "/media/file_1.mpg")
        val second = StalkerVodLink.buildMarker("stalker2", "/media/file_1.mpg")

        assertNotEquals(first, second)
        assertEquals("stalker1" to "/media/file_1.mpg", StalkerVodLink.parseMarker(first!!))
        assertEquals("stalker2" to "/media/file_1.mpg", StalkerVodLink.parseMarker(second!!))
    }

    @Test
    fun `markers survive commands with slashes spaces and query parts`() {
        val cmd = "/media/Some Movie (2021)/file?token=a/b&x=1"
        val marker = StalkerVodLink.buildMarker("stalker1", cmd)

        assertTrue(StalkerVodLink.isMarker(marker!!))
        assertEquals("stalker1" to cmd, StalkerVodLink.parseMarker(marker))
    }

    @Test
    fun `malformed markers and foreign urls are rejected`() {
        assertNull(StalkerVodLink.parseMarker("https://example.com/movie.mp4"))
        assertNull(StalkerVodLink.parseMarker("stalker_vod://stalker1"))
        assertNull(StalkerVodLink.parseMarker("stalker_vod:///cmd"))
        assertNull(StalkerVodLink.parseMarker("stalker_vod://stalker1/"))
        assertNull(StalkerVodLink.buildMarker("stalker1", "   "))
        assertNull(StalkerVodLink.buildMarker("  ", "/media/a.mpg"))
    }

    @Test
    fun `a placeholder counts as a direct source url`() {
        val marker = StalkerVodLink.buildMarker("stalker1", "/media/1.mpg")!!

        assertTrue(isDirectStreamUrl(marker))
        assertTrue(isDirectStreamUrl("https://example.com/a.mp4"))
        assertFalse(isDirectStreamUrl("magnet:?xt=urn:btih:abc"))
        assertFalse(isDirectStreamUrl(null))
        assertFalse(isDirectStreamUrl("   "))
    }
}
