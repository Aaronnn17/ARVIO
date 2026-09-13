package com.arflix.tv.ui.screens.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The decisions behind the filter row, checked without a screen: which separator carries E3,
 * what survives a media-type switch, and where the focus goes inside an open panel.
 */
class DiscoverFiltersTest {

    private val action = MOVIE_GENRES.first { it.id == 28 }
    private val sciFi = MOVIE_GENRES.first { it.id == 878 }
    private val comedy = MOVIE_GENRES.first { it.id == 35 }
    private val music = MOVIE_GENRES.first { it.id == 10402 }

    // ── E3: the separator is the whole feature ──────────────────────────

    @Test fun matchingAllGenresUsesTheCommaThatMeansAnd() {
        assertEquals("28,878", genresParam(listOf(action, sciFi), matchAll = true))
    }

    @Test fun matchingAnyGenreUsesThePipeThatMeansOr() {
        assertEquals("28|878", genresParam(listOf(action, sciFi), matchAll = false))
    }

    @Test fun noGenreMeansNoParameterAtAllRatherThanAnEmptyOne() {
        assertNull(genresParam(emptyList(), matchAll = true))
    }

    // ── The type switch: remap, do not simply drop (FUND C) ─────────────

    @Test fun switchingToSeriesKeepsAGenreThatHasACounterpart() {
        val kept = remapGenresForType(listOf(action), DiscoverType.TV_SHOWS)
        assertEquals(listOf(10759), kept.map { it.id })
    }

    @Test fun switchingToSeriesKeepsAGenreThatIsNumberedTheSameInBothLists() {
        val kept = remapGenresForType(listOf(comedy), DiscoverType.TV_SHOWS)
        assertEquals(listOf(35), kept.map { it.id })
    }

    @Test fun aGenreWithNoSeriesCounterpartIsTheOnlyOneDropped() {
        // "Music" exists for films and not for series — carrying it over would return nothing.
        val kept = remapGenresForType(listOf(action, music), DiscoverType.TV_SHOWS)
        assertEquals(listOf(10759), kept.map { it.id })
    }

    @Test fun switchingBackToMoviesUndoesTheRemap() {
        val toSeries = remapGenresForType(listOf(action), DiscoverType.TV_SHOWS)
        val andBack = remapGenresForType(toSeries, DiscoverType.MOVIES)
        assertEquals(listOf(28), andBack.map { it.id })
    }

    @Test fun animeUsesTheMovieNumberingItsOwnListIsWrittenIn() {
        val kept = remapGenresForType(listOf(action), DiscoverType.ANIME)
        assertEquals(listOf(28), kept.map { it.id })
    }

    @Test fun everyOfferedGenreSurvivesItsOwnType() {
        DiscoverType.entries.forEach { type ->
            val offered = genresFor(type)
            assertEquals(
                "$type must not offer a genre it then drops",
                offered.map { it.id },
                remapGenresForType(offered, type).map { it.id }
            )
        }
    }

    // ── Age rating: movies only ─────────────────────────────────────────

    @Test fun onlyMoviesCanBeFilteredByAge() {
        assertTrue(supportsCertification(DiscoverType.MOVIES))
        assertFalse(supportsCertification(DiscoverType.TV_SHOWS))
        assertFalse(supportsCertification(DiscoverType.ANIME))
    }

    @Test fun theAgeListFollowsTheContentCountryAndFallsBackToNothingWhereThereIsNone() {
        assertEquals(listOf("0", "6", "12", "16", "18"), certificationsForLanguage("de-DE"))
        assertEquals(listOf("G", "PG", "PG-13", "R", "NC-17"), certificationsForLanguage("en-US"))
        assertTrue(certificationsForLanguage("ja-JP").isEmpty())
    }

    // ── Panel navigation ────────────────────────────────────────────────

    @Test fun sidewaysMovementStaysInsideItsRow() {
        // Twelve options, three across: index 2 is the end of the first row.
        assertEquals(2, movePanelFocus(index = 2, count = 12, columns = 3, dx = 1, dy = 0))
        assertEquals(3, movePanelFocus(index = 3, count = 12, columns = 3, dx = -1, dy = 0))
        assertEquals(1, movePanelFocus(index = 0, count = 12, columns = 3, dx = 1, dy = 0))
    }

    @Test fun downMovesOneRowAndStopsAtTheLast() {
        assertEquals(4, movePanelFocus(index = 1, count = 12, columns = 3, dx = 0, dy = 1))
        assertEquals(10, movePanelFocus(index = 10, count = 12, columns = 3, dx = 0, dy = 1))
    }

    @Test fun upFromTheFirstRowLeavesThePanel() {
        assertEquals(PANEL_FOCUS_LEAVE, movePanelFocus(index = 1, count = 12, columns = 3, dx = 0, dy = -1))
        assertEquals(1, movePanelFocus(index = 4, count = 12, columns = 3, dx = 0, dy = -1))
    }

    @Test fun anEmptyPanelCannotTrapTheFocus() {
        assertEquals(PANEL_FOCUS_LEAVE, movePanelFocus(index = 0, count = 0, columns = 3, dx = 0, dy = 1))
    }

    @Test fun aBrokenColumnCountStillMovesSomewhereSensible() {
        assertEquals(1, movePanelFocus(index = 0, count = 5, columns = 0, dx = 0, dy = 1))
    }

    // ── Rating ──────────────────────────────────────────────────────────

    @Test fun aRatingCountsAsSetAsSoonAsAnyOfItsThreeValuesIs() {
        assertFalse(RatingFilter().isSet)
        assertTrue(RatingFilter(min = 7.0).isSet)
        assertTrue(RatingFilter(max = 9.0).isSet)
        assertTrue(RatingFilter(minVotes = 500).isSet)
    }

    @Test fun theVoteFloorStartsAtAnySoFreshReleasesAreNotHiddenByDefault() {
        assertNull(MIN_VOTE_OPTIONS.first())
        assertNull(RatingFilter().minVotes)
    }
}
