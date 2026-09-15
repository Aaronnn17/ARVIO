package com.arflix.tv.ui.screens.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arflix.tv.data.model.MediaItem
import com.arflix.tv.data.model.MediaType
import com.arflix.tv.data.model.Category
import com.arflix.tv.data.repository.MediaRepository
import com.arflix.tv.data.repository.PersonMediaSearchResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import javax.inject.Inject

data class Genre(val id: Int, val name: String)

val MOVIE_GENRES = listOf(
    Genre(28, "Action"), Genre(12, "Adventure"), Genre(16, "Animation"),
    Genre(35, "Comedy"), Genre(80, "Crime"), Genre(99, "Documentary"),
    Genre(18, "Drama"), Genre(10751, "Family"), Genre(14, "Fantasy"),
    Genre(36, "History"), Genre(27, "Horror"), Genre(10402, "Music"),
    Genre(9648, "Mystery"), Genre(10749, "Romance"), Genre(878, "Sci-Fi"),
    Genre(53, "Thriller"), Genre(10752, "War"), Genre(37, "Western")
)
val TV_GENRES = listOf(
    Genre(10759, "Action & Adventure"), Genre(16, "Animation"),
    Genre(35, "Comedy"), Genre(80, "Crime"), Genre(99, "Documentary"),
    Genre(18, "Drama"), Genre(10751, "Family"), Genre(10762, "Kids"),
    Genre(9648, "Mystery"), Genre(10765, "Sci-Fi & Fantasy"),
    Genre(10768, "War & Politics"), Genre(37, "Western")
)
val ALL_GENRES = listOf(
    Genre(28, "Action"), Genre(12, "Adventure"), Genre(16, "Animation"),
    Genre(35, "Comedy"), Genre(80, "Crime"), Genre(99, "Documentary"),
    Genre(18, "Drama"), Genre(10751, "Family"), Genre(14, "Fantasy"),
    Genre(27, "Horror"), Genre(9648, "Mystery"), Genre(10749, "Romance"),
    Genre(878, "Sci-Fi"), Genre(53, "Thriller"), Genre(10752, "War"),
    Genre(37, "Western")
)
val ANIME_GENRES = listOf(
    Genre(28, "Action"), Genre(12, "Adventure"), Genre(35, "Comedy"),
    Genre(18, "Drama"), Genre(14, "Fantasy"), Genre(27, "Horror"),
    Genre(10749, "Romance"), Genre(878, "Sci-Fi"), Genre(9648, "Mystery")
)

data class Country(val code: String, val name: String)
val COUNTRIES = listOf(
    Country("en", "English"), Country("ja", "Japanese"), Country("ko", "Korean"),
    Country("es", "Spanish"), Country("fr", "French"), Country("de", "German"),
    Country("it", "Italian"), Country("pt", "Portuguese"), Country("hi", "Hindi"),
    Country("zh", "Chinese"), Country("tr", "Turkish"), Country("ar", "Arabic"),
    Country("th", "Thai"), Country("nl", "Dutch"), Country("ru", "Russian")
)

enum class DiscoverType(val label: String) { ALL("All"), MOVIES("Movies"), TV_SHOWS("TV Shows"), ANIME("Anime") }
enum class SortOption(val label: String, val apiValue: String) { POPULAR("Popular", "popularity.desc"), TOP_RATED("Top Rated", "vote_average.desc"), NEWEST("Newest", "primary_release_date.desc") }

/** A filter change loads straight away (E4) — debounced so two quick taps cost one load. */
private const val DISCOVER_FILTER_DEBOUNCE_MS = 350L
/** The filtered grid has no sort control yet (that is step 3), so it browses by popularity. */
private const val DISCOVER_GRID_SORT = "popularity.desc"
/** Same floor the "Trending" row uses: keeps single-vote entries out of the grid. */
private const val DISCOVER_GRID_MIN_VOTES = 50
/** TMDB serves at most 500 discover pages; asking beyond that only returns errors. */
private const val TMDB_MAX_DISCOVER_PAGE = 500

// Memoized empty collections to reduce GC pressure
private val EMPTY_MEDIA_ITEMS: List<MediaItem> = emptyList()
private val EMPTY_CATEGORIES: List<Category> = emptyList()
private val EMPTY_LOGO_URLS: Map<String, String> = emptyMap()

data class SearchUiState(
    val query: String = "",
    val isLoading: Boolean = false,
    val results: List<MediaItem> = EMPTY_MEDIA_ITEMS,
    val movieResults: List<MediaItem> = EMPTY_MEDIA_ITEMS,
    val tvResults: List<MediaItem> = EMPTY_MEDIA_ITEMS,
    val personResults: List<Category> = EMPTY_CATEGORIES,
    val cardLogoUrls: Map<String, String> = EMPTY_LOGO_URLS,
    val error: String? = null,
    // Discover rows - always 5 rows, dynamically built from active filters
    val discoverCategories: List<Category> = EMPTY_CATEGORIES,
    val discoverLogoUrls: Map<String, String> = EMPTY_LOGO_URLS,
    val isDiscoverLoading: Boolean = false,
    // Filters. The media type is mandatory while discovering (E2): "All" would need two
    // discover calls with two page counters, and TMDB's sort order stops holding once the
    // two halves are merged — which breaks an endlessly paging grid.
    val selectedType: DiscoverType = DiscoverType.MOVIES,
    val selectedGenre: Genre? = null,
    val selectedCountry: Country? = null,
    // Discover grid - shown instead of the five rows as soon as a filter is set
    val discoverGridItems: List<MediaItem> = EMPTY_MEDIA_ITEMS,
    val isGridLoading: Boolean = false,
    val isGridLoadingMore: Boolean = false,
    val gridEndReached: Boolean = false,
    val gridLoadFailed: Boolean = false,
    // AI
    val aiInterpretation: String? = null,
    val aiResults: List<MediaItem> = EMPTY_MEDIA_ITEMS,
    val isAiSearch: Boolean = false
) {
    /**
     * Rows or grid: the media type alone is not a filter (it is always set), so only a
     * genre or a language switches the browse rows over to the filtered grid.
     */
    val hasDiscoverFilters: Boolean
        get() = selectedGenre != null || selectedCountry != null
}

@HiltViewModel
class SearchViewModel @Inject constructor(
    private val mediaRepository: MediaRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null
    private var discoverJob: Job? = null
    private var filterDebounceJob: Job? = null
    private var gridPage = 0
    private var gridGeneration = 0L
    private var gridJob: Job? = null

    private fun cancelGridLoad() {
        gridGeneration++
        gridJob?.cancel()
        gridJob = null
    }
    private var cachedSuggestionQuery = ""
    private var cachedSuggestionResults: List<MediaItem> = EMPTY_MEDIA_ITEMS
    private var cachedPeopleQuery = ""
    private var cachedPeopleResults: List<Category> = EMPTY_CATEGORIES
    private var activeSearchQuery: String? = null
    private var peopleNeedingCredits: List<PersonMediaSearchResult> = emptyList()

    init { startDiscoverLoad() }

    // ── Discover Rows (5 dynamic rows based on filters) ─────────────────

    private fun loadDiscoverRows() {
        discoverJob?.cancel()
        val state = _uiState.value
        _uiState.value = state.copy(isDiscoverLoading = true)

        discoverJob = viewModelScope.launch {
            try {
                val type = state.selectedType
                val genre = state.selectedGenre?.id?.toString()
                val lang = state.selectedCountry?.code
                val isAnime = type == DiscoverType.ANIME

                val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
                val cal = java.util.Calendar.getInstance()
                cal.add(java.util.Calendar.DAY_OF_YEAR, -90)
                val threeMonthsAgo = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(cal.time)
                cal.time = java.util.Date()
                cal.add(java.util.Calendar.YEAR, -1)
                val oneYearAgo = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(cal.time)

                val categories = withContext(Dispatchers.IO) {
                    coroutineScope {
                        // Row titles stay English: they are part of the Category id used
                        // as the row's focus key. SearchScreen localizes them for display
                        // only (localizedDiscoverRowTitle).
                        // Row 1: Trending - popular with minimum votes to filter garbage
                        val row1 = async { buildRow("Trending", type, genre, "popularity.desc", 50, lang, isAnime, 1, releaseDateLte = today) }
                        // Row 2: Popular This Year - recent + popular, no obscure stuff
                        val row2 = async { buildRow("Popular This Year", type, genre, "popularity.desc", 20, lang, isAnime, 1, releaseDateGte = oneYearAgo, releaseDateLte = today) }
                        // Row 3: Top Rated - high quality, well-known titles
                        val row3 = async { buildRow("Top Rated", type, genre, "vote_average.desc", 1000, lang, isAnime, 1, releaseDateLte = today) }
                        // Row 4: New Releases - last 90 days ONLY, must be actually released (date <= today)
                        val row4 = async { buildRow("New Releases", type, genre, "popularity.desc", 10, lang, isAnime, 1, releaseDateGte = threeMonthsAgo, releaseDateLte = today) }
                        // Row 5: Hidden Gems - good ratings but less mainstream
                        val row5 = async { buildRow("Hidden Gems", type, genre, "vote_average.desc", 200, lang, isAnime, 2, releaseDateLte = today) }
                        listOfNotNull(row1.await(), row2.await(), row3.await(), row4.await(), row5.await())
                    }
                }
                categories.forEach { cat -> cat.items.forEach { mediaRepository.cacheItem(it) } }
                _uiState.value = _uiState.value.copy(discoverCategories = categories, isDiscoverLoading = false)
                // Fetch logos for top items in each row (background, non-blocking)
                launch(Dispatchers.IO) {
                    val slots = Semaphore(3)
                    val allItems = categories.flatMap { it.items }.distinctBy { "${it.mediaType}_${it.id}" }.take(24)
                    val logos = allItems.map { item ->
                        async {
                            val key = "${item.mediaType}_${item.id}"
                            val logo = slots.withPermit {
                                try { withTimeoutOrNull(2_000) { mediaRepository.getLogoUrl(item.mediaType, item.id) } }
                                catch (e: CancellationException) { throw e }
                                catch (_: Exception) { null }
                            }
                            if (!logo.isNullOrBlank()) {
                                mediaRepository.cacheLogoUrl(item.mediaType, item.id, logo)
                                key to logo
                            } else null
                        }
                    }.awaitAll().filterNotNull().toMap()
                    _uiState.update { it.copy(discoverLogoUrls = it.discoverLogoUrls + logos) }
                }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isDiscoverLoading = false)
            }
        }
    }

    private suspend fun buildRow(
        title: String, type: DiscoverType, genre: String?, sort: String,
        minVotes: Int?, lang: String?, isAnime: Boolean, page: Int,
        releaseDateGte: String? = null, releaseDateLte: String? = null
    ): Category? {
        return try {
            val items = fetchDiscoverPage(type, genre, sort, minVotes, lang, page, releaseDateGte, releaseDateLte)
            if (items.isEmpty()) null else Category(id = "${type}_${title}_${genre}_${lang}_$page", title = title, items = items.take(20))
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { null }
    }

    /**
     * The single place that turns a filter set into TMDB items. Both the browse rows and the
     * filtered grid go through it, so the movies/series/anime/all split and the movie→series
     * genre remap exist exactly once instead of drifting apart in two copies.
     */
    private suspend fun fetchDiscoverPage(
        type: DiscoverType, genre: String?, sort: String, minVotes: Int?, lang: String?, page: Int,
        releaseDateGte: String? = null, releaseDateLte: String? = null
    ): List<MediaItem> {
        val movieGenre = genre
        val tvGenre = mapMovieGenreToTvGenre(genre)
        return when (type) {
            DiscoverType.MOVIES -> mediaRepository.discoverMovies(movieGenre, sort, minVotes, page, language = lang, releaseDateLte = releaseDateLte, releaseDateGte = releaseDateGte)
            DiscoverType.TV_SHOWS -> mediaRepository.discoverTv(tvGenre, sort, minVotes, page, language = lang, airDateLte = releaseDateLte, airDateGte = releaseDateGte)
            DiscoverType.ANIME -> {
                val animeGenre = buildAnimeGenre(tvGenre)
                mediaRepository.discoverTv(animeGenre, sort, minVotes, page, language = lang, keywords = "210024", airDateLte = releaseDateLte, airDateGte = releaseDateGte)
            }
            DiscoverType.ALL -> {
                coroutineScope {
                    val m = async { mediaRepository.discoverMovies(movieGenre, sort, minVotes, page, language = lang, releaseDateLte = releaseDateLte, releaseDateGte = releaseDateGte) }
                    val t = async { mediaRepository.discoverTv(tvGenre, sort, minVotes, page, language = lang, airDateLte = releaseDateLte, airDateGte = releaseDateGte) }
                    interleave(m.await(), t.await())
                }
            }
        }
    }

    private fun mapMovieGenreToTvGenre(genre: String?): String? = when (genre) {
        "28" -> "10759"
        "14", "878" -> "10765"
        "10752" -> "10768"
        else -> genre
    }

    private fun buildAnimeGenre(genre: String?): String = when (genre) {
        null, "16" -> "16"
        else -> "16,$genre"
    }

    // ── Discover grid (shown as soon as a filter is set) ────────────────

    private fun loadDiscoverGrid() {
        discoverJob?.cancel()
        cancelGridLoad()
        gridPage = 0
        _uiState.value = _uiState.value.copy(isGridLoading = true, isGridLoadingMore = false, gridEndReached = false, gridLoadFailed = false)
        val generation = gridGeneration
        gridJob = viewModelScope.launch { fetchGridPage(append = false, generation) }
    }

    /**
     * Endless paging (H9). The grid asks for the next TMDB page when the user nears its end;
     * everything that could turn that into a request storm is guarded here.
     */
    fun loadMoreDiscoverGrid() {
        val state = _uiState.value
        if (state.query.isNotEmpty() || !state.hasDiscoverFilters) return
        if (state.isGridLoading || state.isGridLoadingMore || state.gridEndReached || state.gridLoadFailed) return
        _uiState.value = state.copy(isGridLoadingMore = true)
        val generation = gridGeneration
        gridJob = viewModelScope.launch { fetchGridPage(append = true, generation) }
    }

    fun retryDiscoverGrid() {
        val state = _uiState.value
        if (!state.gridLoadFailed || state.query.isNotEmpty() || !state.hasDiscoverFilters) return
        val append = gridPage > 0
        _uiState.value = state.copy(gridLoadFailed = false, isGridLoading = !append, isGridLoadingMore = append)
        val generation = gridGeneration
        gridJob = viewModelScope.launch { fetchGridPage(append, generation) }
    }

    private suspend fun fetchGridPage(append: Boolean, generation: Long) {
        val started = _uiState.value
        val signature = filterSignature(started)
        val page = gridPage + 1
        try {
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
            val items = withContext(Dispatchers.IO) {
                fetchDiscoverPage(
                    type = started.selectedType,
                    genre = started.selectedGenre?.id?.toString(),
                    sort = DISCOVER_GRID_SORT,
                    minVotes = DISCOVER_GRID_MIN_VOTES,
                    lang = started.selectedCountry?.code,
                    page = page,
                    releaseDateLte = today
                )
            }
            val current = _uiState.value
            // The filter moved on while this page was in flight — its answer is stale.
            if (generation != gridGeneration || filterSignature(current) != signature || current.query.isNotEmpty()) return
            items.forEach { mediaRepository.cacheItem(it) }
            val existing = if (append) current.discoverGridItems else EMPTY_MEDIA_ITEMS
            val known = existing.mapTo(HashSet()) { it.mediaType to it.id }
            val fresh = items.filter { known.add(it.mediaType to it.id) }
            gridPage = page
            _uiState.value = current.copy(
                discoverGridItems = existing + fresh,
                isGridLoading = false,
                isGridLoadingMore = false,
                gridEndReached = items.isEmpty() || page >= TMDB_MAX_DISCOVER_PAGE
            )
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) {
            val current = _uiState.value
            if (generation != gridGeneration || filterSignature(current) != signature || current.query.isNotEmpty()) return
            // Keep the page counter and existing titles; only explicit Retry resumes loading.
            _uiState.value = current.copy(isGridLoading = false, isGridLoadingMore = false, gridLoadFailed = true)
        }
    }

    private fun filterSignature(state: SearchUiState): String =
        "${state.selectedType}|${state.selectedGenre?.id}|${state.selectedCountry?.code}"

    // ── Filters → reload rows or grid ───────────────────────────────────

    /**
     * One entry point for every filter change. E4: no "apply" button — the change loads
     * immediately, debounced by [DISCOVER_FILTER_DEBOUNCE_MS] so two quick taps cost one load
     * instead of two (and spare the logo requests of the discarded one).
     */
    private fun applyDiscoverSelection(debounce: Boolean = true) {
        cancelGridLoad()
        filterDebounceJob?.cancel()
        discoverJob?.cancel()
        gridPage = 0
        val state = _uiState.value
        _uiState.value = state.copy(
            discoverCategories = EMPTY_CATEGORIES,
            discoverLogoUrls = EMPTY_LOGO_URLS,
            discoverGridItems = EMPTY_MEDIA_ITEMS,
            isDiscoverLoading = !state.hasDiscoverFilters,
            isGridLoading = state.hasDiscoverFilters,
            isGridLoadingMore = false,
            gridEndReached = false,
            gridLoadFailed = false
        )
        if (!debounce) { startDiscoverLoad(); return }
        filterDebounceJob = viewModelScope.launch {
            delay(DISCOVER_FILTER_DEBOUNCE_MS)
            startDiscoverLoad()
        }
    }

    private fun startDiscoverLoad() {
        if (_uiState.value.hasDiscoverFilters) loadDiscoverGrid() else loadDiscoverRows()
    }

    fun selectType(type: DiscoverType) {
        // Genre ids differ per media type (movie "Action" 28 vs. series "Action & Adventure"
        // 10759), and not every movie genre has a series counterpart — so switching the type
        // drops the genre instead of carrying over one that would return nothing.
        _uiState.value = _uiState.value.copy(selectedType = type, selectedGenre = null)
        applyDiscoverSelection()
    }

    fun setDiscoverFilters(type: DiscoverType, genre: Genre?, country: Country?) {
        _uiState.value = _uiState.value.copy(selectedType = type, selectedGenre = genre, selectedCountry = country)
        applyDiscoverSelection()
    }

    fun selectGenre(genre: Genre?) {
        _uiState.value = _uiState.value.copy(selectedGenre = genre)
        applyDiscoverSelection()
    }

    fun selectCountry(country: Country?) {
        _uiState.value = _uiState.value.copy(selectedCountry = country)
        applyDiscoverSelection()
    }

    // ── Search + AI ─────────────────────────────────────────────────────

    fun addChar(char: String) { updateQuery(_uiState.value.query + char) }
    fun deleteChar() { if (_uiState.value.query.isNotEmpty()) updateQuery(_uiState.value.query.dropLast(1)) }

    fun updateQuery(newQuery: String) {
        if (newQuery == _uiState.value.query) return
        searchJob?.cancel()
        activeSearchQuery = null
        _uiState.value = _uiState.value.copy(query = newQuery, isAiSearch = false, aiInterpretation = null, aiResults = EMPTY_MEDIA_ITEMS)
        if (newQuery.trim().isEmpty()) {
            clearSearch()
            return
        }
        filterDebounceJob?.cancel()
        discoverJob?.cancel()
        cancelGridLoad()
        _uiState.value = _uiState.value.copy(isLoading = true, isDiscoverLoading = false,
            isGridLoading = false, isGridLoadingMore = false, error = null, results = EMPTY_MEDIA_ITEMS,
            movieResults = EMPTY_MEDIA_ITEMS, tvResults = EMPTY_MEDIA_ITEMS,
            personResults = EMPTY_CATEGORIES, cardLogoUrls = EMPTY_LOGO_URLS)
        debounceSearch()
    }

    fun search() {
        val query = _uiState.value.query.trim(); if (query.isEmpty()) return
        if (searchJob?.isActive == true && activeSearchQuery == query && _uiState.value.error == null) return
        val aiQuery = parseSmartQuery(query); if (aiQuery != null) { executeSmartSearch(aiQuery); return }
        searchJob?.cancel()
        activeSearchQuery = query
        searchJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = it.results.isEmpty(), error = null, isAiSearch = false) }
            try {
                if (cachedSuggestionQuery != query || cachedPeopleQuery != query) {
                    val response = withContext(Dispatchers.IO) { mediaRepository.searchWithPeople(query) }
                    val sorted = withContext(Dispatchers.Default) { rankSearchResults(query, response.items) }
                    cachedSuggestionQuery = query
                    cachedSuggestionResults = sorted
                    cachedPeopleQuery = query
                    peopleNeedingCredits = response.people.filter { it.items.isEmpty() }
                    cachedPeopleResults = response.people.filter { it.items.isNotEmpty() }
                        .map { Category("person_${it.personId}", it.name, it.items) }
                }
                val sorted = cachedSuggestionResults
                val peopleRows = cachedPeopleResults
                _uiState.update { it.copy(isLoading = sorted.isEmpty() && peopleRows.isEmpty() && peopleNeedingCredits.isNotEmpty(), results = sorted,
                    movieResults = sorted.filter { item -> item.mediaType == MediaType.MOVIE },
                    tvResults = sorted.filter { item -> item.mediaType == MediaType.TV }, personResults = peopleRows) }

                // Cards are usable now. Bounded, cancellable logo enrichment never replaces the rows.
                val slots = Semaphore(3)
                val top = (sorted + peopleRows.flatMap { it.items }).distinctBy { it.mediaType to it.id }.take(12)
                coroutineScope {
                    launch {
                        for (person in peopleNeedingCredits) {
                            val credits = try {
                                withTimeoutOrNull(2_000) {
                                    withContext(Dispatchers.IO) { mediaRepository.getPersonDetails(person.personId).knownFor }
                                }.orEmpty()
                            } catch (e: CancellationException) { throw e }
                            catch (_: Exception) { emptyList() }
                            if (credits.isNotEmpty()) {
                                val row = Category("person_${person.personId}", person.name, credits.distinctBy { it.mediaType to it.id })
                                cachedPeopleResults = cachedPeopleResults + row
                                _uiState.update { it.copy(personResults = it.personResults + row, isLoading = false) }
                            }
                        }
                        peopleNeedingCredits = emptyList()
                        _uiState.update { it.copy(isLoading = false) }
                    }
                    top.forEach { item -> launch {
                        val key = "${item.mediaType}_${item.id}"
                        val logo = slots.withPermit {
                            try {
                                withTimeoutOrNull(2_000) {
                                    withContext(Dispatchers.IO) { mediaRepository.getLogoUrl(item.mediaType, item.id) }
                                }
                            } catch (e: CancellationException) { throw e }
                            catch (_: Exception) { null }
                        }
                        if (!logo.isNullOrBlank()) {
                            _uiState.update { it.copy(cardLogoUrls = it.cardLogoUrls + (key to logo)) }
                        }
                    } }
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    private data class SmartQuery(val interpretation: String, val type: DiscoverType, val genreId: String?, val sort: String, val minVotes: Int?, val limit: Int?, val similarTo: String?)

    private fun parseSmartQuery(raw: String): SmartQuery? {
        if (!isSmartDiscoveryQuery(raw)) return null
        val q = raw.lowercase().trim()
        val genreKeywords = mapOf("horror" to "27", "comedy" to "35", "action" to "28", "drama" to "18", "thriller" to "53", "sci-fi" to "878", "science fiction" to "878", "romance" to "10749", "animation" to "16", "anime" to "16", "documentary" to "99", "crime" to "80", "fantasy" to "14", "adventure" to "12", "mystery" to "9648", "war" to "10752", "western" to "37", "family" to "10751", "history" to "36")
        val likeMatch = SearchRegexes.LIKE_MATCH_REGEX.find(q)
        if (likeMatch != null) { val t = likeMatch.groupValues[1].trim(); return SmartQuery("Similar to \"${t.replaceFirstChar { it.uppercase() }}\"", if (q.contains("show") || q.contains("series")) DiscoverType.TV_SHOWS else DiscoverType.MOVIES, null, "popularity.desc", null, null, t) }
        if (!(q.contains("top") || q.contains("best") || q.contains("popular") || q.contains("trending") || q.contains("new") || q.contains("latest"))) return null
        var gId: String? = null; var gName: String? = null; for ((kw, id) in genreKeywords) { if (q.contains(kw)) { gId = id; gName = kw.replaceFirstChar { it.uppercase() }; break } }
        if (gId == null && !q.contains("movie") && !q.contains("show") && !q.contains("series") && !q.contains("film") && !q.contains("trending") && !q.contains("anime")) return null
        val isAnime = q.contains("anime"); val isTV = q.contains("show") || q.contains("series"); val isMovie = q.contains("movie") || q.contains("film")
        val type = when { isAnime -> DiscoverType.ANIME; isTV && !isMovie -> DiscoverType.TV_SHOWS; isMovie && !isTV -> DiscoverType.MOVIES; else -> DiscoverType.ALL }
        val limit = SearchRegexes.LIMIT_MATCH_REGEX.find(q)?.groupValues?.get(1)?.toIntOrNull()
        val sort = when { q.contains("best") || q.contains("top rated") || limit != null -> "vote_average.desc"; q.contains("new") || q.contains("latest") -> if (isTV || isAnime) "first_air_date.desc" else "primary_release_date.desc"; else -> "popularity.desc" }
        val parts = mutableListOf<String>(); if (limit != null) parts.add("Top $limit"); if (sort == "vote_average.desc" && limit == null) parts.add("Best") else if (sort.contains("date")) parts.add("Newest") else parts.add("Popular")
        if (gName != null) parts.add(gName); parts.add(when(type) { DiscoverType.MOVIES -> "Movies"; DiscoverType.TV_SHOWS -> "Series"; DiscoverType.ANIME -> "Anime"; DiscoverType.ALL -> "Movies & Series" })
        return SmartQuery(parts.joinToString(" "), type, gId, sort, if (sort == "vote_average.desc") 500 else null, limit, null)
    }

    private fun executeSmartSearch(sq: SmartQuery) {
        searchJob?.cancel(); searchJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, isAiSearch = true, aiInterpretation = sq.interpretation, error = null, movieResults = EMPTY_MEDIA_ITEMS, tvResults = EMPTY_MEDIA_ITEMS, personResults = EMPTY_CATEGORIES)
            try {
                val items = withContext(Dispatchers.IO) {
                    if (sq.similarTo != null) { val r = mediaRepository.search(sq.similarTo); val m = r.firstOrNull(); if (m != null) mediaRepository.getSimilar(m.mediaType, m.id) else EMPTY_MEDIA_ITEMS }
                    else {
                        val tvGenre = mapMovieGenreToTvGenre(sq.genreId)
                        when (sq.type) {
                            DiscoverType.MOVIES -> mediaRepository.discoverMovies(sq.genreId, sq.sort, sq.minVotes, 1)
                            DiscoverType.TV_SHOWS -> mediaRepository.discoverTv(tvGenre, sq.sort, sq.minVotes, 1)
                            DiscoverType.ANIME -> mediaRepository.discoverTv(buildAnimeGenre(tvGenre), sq.sort, sq.minVotes, 1, keywords = "210024")
                            DiscoverType.ALL -> {
                                coroutineScope {
                                    val a = async { mediaRepository.discoverMovies(sq.genreId, sq.sort, sq.minVotes, 1) }
                                    val b = async { mediaRepository.discoverTv(tvGenre, sq.sort, sq.minVotes, 1) }
                                    interleave(a.await(), b.await())
                                }
                            }
                        }
                    }
                }
                items.forEach { mediaRepository.cacheItem(it) }
                _uiState.value = _uiState.value.copy(isLoading = false, aiResults = if (sq.limit != null) items.take(sq.limit) else items)
            } catch (e: Exception) { if (e is kotlinx.coroutines.CancellationException) throw e
 _uiState.value = _uiState.value.copy(isLoading = false, error = e.message) }
        }
    }

    private fun debounceSearch() { searchJob?.cancel(); searchJob = viewModelScope.launch { delay(260); search() } }

    fun clearSearch() {
        cancelGridLoad()
        searchJob?.cancel()
        activeSearchQuery = null
        peopleNeedingCredits = emptyList()
        cachedSuggestionQuery = ""; cachedSuggestionResults = EMPTY_MEDIA_ITEMS
        cachedPeopleQuery = ""; cachedPeopleResults = EMPTY_CATEGORIES
        _uiState.value = _uiState.value.copy(query = "", isLoading = false, isGridLoading = false, isGridLoadingMore = false, results = EMPTY_MEDIA_ITEMS,
            movieResults = EMPTY_MEDIA_ITEMS, tvResults = EMPTY_MEDIA_ITEMS, personResults = EMPTY_CATEGORIES,
            cardLogoUrls = EMPTY_LOGO_URLS, error = null, isAiSearch = false, aiInterpretation = null, aiResults = EMPTY_MEDIA_ITEMS)
        val state = _uiState.value
        if (state.hasDiscoverFilters) {
            if (state.discoverGridItems.isEmpty()) loadDiscoverGrid()
        } else if (state.discoverCategories.isEmpty()) {
            loadDiscoverRows()
        }
    }
    fun getGenresForType(): List<Genre> = when (_uiState.value.selectedType) { DiscoverType.MOVIES -> MOVIE_GENRES; DiscoverType.TV_SHOWS -> TV_GENRES; DiscoverType.ALL -> ALL_GENRES; DiscoverType.ANIME -> ANIME_GENRES }
    private fun interleave(a: List<MediaItem>, b: List<MediaItem>): List<MediaItem> { val r = mutableListOf<MediaItem>(); for (i in 0 until maxOf(a.size, b.size)) { if (i < a.size) r.add(a[i]); if (i < b.size) r.add(b[i]) }; return r }
}

private object SearchRegexes {
    val LIKE_MATCH_REGEX = Regex("(?:movies?|shows?|series|films?)\\s+like\\s+(.+)", RegexOption.IGNORE_CASE)
    val LIMIT_MATCH_REGEX = Regex("top\\s+(\\d+)", RegexOption.IGNORE_CASE)
}
