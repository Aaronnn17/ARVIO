package com.arflix.tv.ui.screens.search

import androidx.lifecycle.ViewModelStore
import com.arflix.tv.data.model.MediaItem
import com.arflix.tv.data.model.MediaType
import com.arflix.tv.data.repository.MediaRepository
import com.arflix.tv.data.repository.TraktRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Step 2 of the combined search/discover page: as soon as a filter is set the
 * five browse rows are replaced by one endlessly paging grid.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DiscoverGridTest {
    private val repository = mockk<MediaRepository>(relaxed = true)
    private val trakt = mockk<TraktRepository>(relaxed = true)
    private val store = ViewModelStore()
    private lateinit var model: SearchViewModel

    private fun movie(id: Int) = MediaItem(id = id, title = "Movie $id", mediaType = MediaType.MOVIE)
    private fun show(id: Int) = MediaItem(id = id, title = "Show $id", mediaType = MediaType.TV)
    private val action = MOVIE_GENRES.first { it.id == 28 }

    @Before fun setUp() {
        Dispatchers.setMain(Dispatchers.Unconfined)
        coEvery { repository.getLogoUrl(any<MediaType>(), any()) } returns null
        coEvery { repository.discoverMovies(any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()) } returns emptyList()
        coEvery { repository.discoverTv(any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()) } returns emptyList()
        model = SearchViewModel(repository, trakt)
        store.put("search", model)
    }

    @After fun tearDown() {
        store.clear()
        Dispatchers.resetMain()
    }

    @Test fun noFilterKeepsTheBrowseRowsAndNoGrid() = runBlocking {
        assertFalse(model.uiState.value.hasDiscoverFilters)
        assertTrue(model.uiState.value.discoverGridItems.isEmpty())
    }

    @Test fun settingAGenreSwitchesFromRowsToTheGrid() = runBlocking {
        coEvery {
            repository.discoverMovies(genres = "28", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(1), movie(2))

        model.toggleGenre(action)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.size == 2 } }

        assertTrue(state.hasDiscoverFilters)
        assertTrue(state.discoverCategories.isEmpty())
        assertFalse(state.isGridLoading)
        assertEquals(listOf(1, 2), state.discoverGridItems.map { it.id })
    }

    @Test fun loadMoreAppendsTheNextPageAndDropsDuplicates() = runBlocking {
        coEvery {
            repository.discoverMovies(genres = "28", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(1), movie(2))
        coEvery {
            repository.discoverMovies(genres = "28", page = 2, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(2), movie(3))

        model.toggleGenre(action)
        withTimeout(5_000) { model.uiState.first { it.discoverGridItems.size == 2 } }
        model.loadMoreDiscoverGrid()
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.size == 3 } }

        assertEquals(listOf(1, 2, 3), state.discoverGridItems.map { it.id })
        assertFalse(state.isGridLoadingMore)
    }

    @Test fun anEmptyPageEndsThePagingSoTheGridStopsAsking() = runBlocking {
        coEvery {
            repository.discoverMovies(genres = "28", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns emptyList()

        model.toggleGenre(action)
        withTimeout(5_000) { model.uiState.first { it.gridEndReached } }
        model.loadMoreDiscoverGrid()
        model.loadMoreDiscoverGrid()

        coVerify(exactly = 0) {
            repository.discoverMovies(genres = "28", page = 2, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        }
    }

    @Test fun clearingTheGenreBringsTheRowsBack() = runBlocking {
        coEvery {
            repository.discoverMovies(genres = "28", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(1))
        coEvery {
            repository.discoverMovies(genres = null, page = any(), sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(9))

        model.toggleGenre(action)
        withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }
        model.toggleGenre(action)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverCategories.isNotEmpty() } }

        assertFalse(state.hasDiscoverFilters)
        assertTrue(state.discoverGridItems.isEmpty())
    }

    @Test fun theGridFollowsTheMediaTypeAndUsesTheSeriesGenreId() = runBlocking {
        coEvery {
            repository.discoverTv(genres = "10759", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), airDateLte = any(), airDateGte = any(), minVoteAverage = any(), maxVoteAverage = any())
        } returns listOf(show(5))

        model.selectType(DiscoverType.TV_SHOWS)
        model.toggleGenre(action)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        assertEquals(listOf(5), state.discoverGridItems.map { it.id })
    }

    // ── Step 3: the six filters the new row adds ────────────────────────

    @Test fun twoGenresAreSentAsOneAndedValue() = runBlocking {
        val sciFi = MOVIE_GENRES.first { it.id == 878 }
        coEvery {
            repository.discoverMovies(genres = "28,878", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(1))

        model.toggleGenre(action)
        model.toggleGenre(sciFi)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        assertEquals(listOf(28, 878), state.selectedGenres.map { it.id })
        assertTrue(state.matchAllGenres)
    }

    @Test fun theSortChipReachesTheGridRequest() = runBlocking {
        coEvery {
            repository.discoverMovies(genres = "28", sortBy = "vote_average.desc", page = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(7))

        model.toggleGenre(action)
        model.selectSort(SortOption.TOP_RATED)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.map { item -> item.id } == listOf(7) } }

        assertEquals(SortOption.TOP_RATED, state.sortOption)
    }

    @Test fun theRatingRangeAndVoteFloorBothReachTheRequest() = runBlocking {
        coEvery {
            repository.discoverMovies(minVoteAverage = 7.0, maxVoteAverage = 9.0, minVoteCount = 500, genres = any(), sortBy = any(), page = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(8))

        model.setRating(RatingFilter(min = 7.0, max = 9.0, minVotes = 500))
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        assertTrue(state.hasDiscoverFilters)
        assertEquals(listOf(8), state.discoverGridItems.map { it.id })
    }

    /** A year is an explicit ask, so the "nothing unreleased" cut-off has to step aside for it. */
    @Test fun askingForAYearDropsTheReleasedUpToTodayLimit() = runBlocking {
        coEvery {
            repository.discoverMovies(year = 1999, releaseDateLte = null, genres = any(), sortBy = any(), minVoteCount = any(), page = any(), language = any(), keywords = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(11))

        model.selectYear(1999)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        assertEquals(listOf(11), state.discoverGridItems.map { it.id })
    }

    @Test fun anAgeRatingIsNeverSentForSeriesBecauseTmdbHasNoSuchFilter() = runBlocking {
        model.selectCertification("16")
        assertEquals("16", model.uiState.value.certification)

        model.selectType(DiscoverType.TV_SHOWS)
        assertNull("the age filter cannot survive the switch to series", model.uiState.value.certification)

        model.selectCertification("16")
        assertNull("and it cannot be set again while series are shown", model.uiState.value.certification)
    }

    @Test fun hideWatchedDropsWatchedTitlesAndKeepsPagingUntilSomethingIsLeft() = runBlocking {
        every { trakt.getWatchedMoviesFromCache() } returns setOf(1, 2)
        coEvery {
            repository.discoverMovies(page = 1, genres = any(), sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(1), movie(2))
        coEvery {
            repository.discoverMovies(page = 2, genres = any(), sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), releaseDateLte = any(), releaseDateGte = any(), minVoteAverage = any(), maxVoteAverage = any(), certificationCountry = any(), certificationLte = any())
        } returns listOf(movie(3))

        model.setHideWatched(true)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        // Page 1 held nothing but watched films, so a page of only-watched results must not be
        // mistaken for the end of the list.
        assertEquals(listOf(3), state.discoverGridItems.map { it.id })
        assertFalse(state.gridEndReached)
    }

    @Test fun clearingEveryFilterBringsTheRowsBackInOneStep() = runBlocking {
        model.toggleGenre(action)
        model.selectYear(2001)
        withTimeout(5_000) { model.uiState.first { it.hasDiscoverFilters } }

        model.clearDiscoverFilters()
        val state = withTimeout(5_000) { model.uiState.first { !it.hasDiscoverFilters } }

        assertTrue(state.selectedGenres.isEmpty())
        assertNull(state.year)
        assertTrue(state.discoverGridItems.isEmpty())
    }
}
