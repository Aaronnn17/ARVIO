package com.arflix.tv.ui.screens.search

import androidx.lifecycle.ViewModelStore
import com.arflix.tv.data.model.MediaItem
import com.arflix.tv.data.model.MediaType
import com.arflix.tv.data.repository.MediaRepository
import io.mockk.coEvery
import io.mockk.coVerify
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
        model = SearchViewModel(repository)
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

        model.selectGenre(action)
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

        model.selectGenre(action)
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

        model.selectGenre(action)
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

        model.selectGenre(action)
        withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }
        model.selectGenre(null)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverCategories.isNotEmpty() } }

        assertFalse(state.hasDiscoverFilters)
        assertTrue(state.discoverGridItems.isEmpty())
    }

    @Test fun theGridFollowsTheMediaTypeAndUsesTheSeriesGenreId() = runBlocking {
        coEvery {
            repository.discoverTv(genres = "10759", page = 1, sortBy = any(), minVoteCount = any(), language = any(), year = any(), keywords = any(), airDateLte = any(), airDateGte = any(), minVoteAverage = any(), maxVoteAverage = any())
        } returns listOf(show(5))

        model.setDiscoverFilters(DiscoverType.TV_SHOWS, action, null)
        val state = withTimeout(5_000) { model.uiState.first { it.discoverGridItems.isNotEmpty() } }

        assertEquals(listOf(5), state.discoverGridItems.map { it.id })
    }
}
