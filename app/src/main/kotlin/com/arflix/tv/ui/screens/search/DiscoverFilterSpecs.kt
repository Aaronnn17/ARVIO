package com.arflix.tv.ui.screens.search

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.arflix.tv.R
import com.arflix.tv.ui.components.movieGenreNameRes
import com.arflix.tv.ui.components.tvGenreNameRes
import java.util.Calendar

/**
 * Builds the discover row and its panels out of the current filter state.
 *
 * It sits beside the screen rather than inside it so the shape of the row — which chip, which
 * icon, what a set chip says — can be read in one place instead of being spread through a
 * thousand-line composable.
 */

/** Every action the row can trigger, so the specs stay free of the view model. */
internal data class DiscoverFilterActions(
    val onSelectType: (DiscoverType) -> Unit,
    val onToggleGenre: (Genre) -> Unit,
    val onMatchAllGenres: (Boolean) -> Unit,
    val onSelectSort: (SortOption) -> Unit,
    val onSetRating: (RatingFilter) -> Unit,
    val onSelectYear: (Int?) -> Unit,
    val onSelectCertification: (String?) -> Unit,
    val onToggleHideWatched: () -> Unit,
    val onOpenPanel: (DiscoverFilterId) -> Unit
)

/** Rating steps offered in the panel — whole and half points, which is how people say it. */
private val RATING_STEPS = listOf(5.0, 6.0, 7.0, 8.0, 9.0)
private val RATING_CEILINGS = listOf(6.0, 7.0, 8.0, 9.0, 10.0)

/**
 * Display-only localization of a TMDB genre name.
 *
 * The media type decides which table is asked. Asking the movie table for a series genre is
 * exactly how "Action & Adventure", "Kids", "Sci-Fi & Fantasy" and "War & Politics" ended up
 * untranslated in the German app, so the type travels with the id here.
 */
@Composable
internal fun Genre.localizedNameFor(type: DiscoverType): String {
    val res = when (type) {
        DiscoverType.TV_SHOWS -> tvGenreNameRes(id) ?: movieGenreNameRes(id)
        else -> movieGenreNameRes(id) ?: tvGenreNameRes(id)
    }
    return if (res != null) stringResource(res) else name
}

/** Localized name of a sort order. */
@Composable
internal fun SortOption.localizedLabel(): String = stringResource(
    when (this) {
        SortOption.POPULAR -> R.string.search_sort_popular
        SortOption.TOP_RATED -> R.string.search_sort_top_rated
        SortOption.NEWEST -> R.string.search_sort_newest
    }
)

/**
 * The seven chips of the approved design, in its order.
 *
 * The draft also shows a shortened row while the user is typing — media type and year, the only
 * two filters TMDB's search endpoints accept. That row is not built here, and the reason is
 * technical rather than a decision: the search path goes through `search/multi`, which takes a
 * query and nothing else. A year filter there means replacing that one call with separate
 * `search/movie` and `search/tv` calls, which changes how search results are ranked. That is its
 * own change, not part of a filter row, so while typing the row stays away as it does today.
 */
@Composable
internal fun discoverChips(
    state: SearchUiState,
    certifications: List<String>,
    actions: DiscoverFilterActions
): List<DiscoverChip> = listOf(
    typeChip(state, actions),
    genreChip(state, actions),
    sortChip(state, actions),
    ratingChip(state, actions),
    yearChip(state, actions),
    certificationChip(state, certifications, actions),
    hideWatchedChip(state, actions)
)

/** The three media types the app knows, in the order the row shows them. */
private val TYPES = listOf(DiscoverType.MOVIES, DiscoverType.TV_SHOWS, DiscoverType.ANIME)

@Composable
private fun typeChip(state: SearchUiState, actions: DiscoverFilterActions): DiscoverChip {
    val current = TYPES.indexOf(state.selectedType).coerceAtLeast(0)
    return DiscoverChip(
        id = DiscoverFilterId.TYPE,
        key = "type",
        label = typeLabel(state.selectedType),
        hasPanel = false,
        // The type is always set, so it is never the white "a filter is on" chip — that colour
        // has to keep meaning "this narrows the list", or the row stops saying anything.
        isSet = false,
        segments = TYPES.map { typeLabel(it) },
        selectedSegment = current,
        onActivate = { actions.onSelectType(TYPES[(current + 1) % TYPES.size]) }
    )
}

@Composable
private fun typeLabel(type: DiscoverType): String = stringResource(
    when (type) {
        DiscoverType.MOVIES -> R.string.movies
        DiscoverType.TV_SHOWS -> R.string.tv_shows
        DiscoverType.ANIME -> R.string.search_filter_anime
        DiscoverType.ALL -> R.string.search_filter_all
    }
)

@Composable
private fun genreChip(state: SearchUiState, actions: DiscoverFilterActions): DiscoverChip {
    val names = state.selectedGenres.map { it.localizedNameFor(state.selectedType) }
    return DiscoverChip(
        id = DiscoverFilterId.GENRE,
        key = "genre",
        label = stringResource(R.string.search_filter_genre),
        value = names.joinToString(", "),
        icon = Icons.Default.LocalOffer,
        isSet = state.selectedGenres.isNotEmpty(),
        onActivate = { actions.onOpenPanel(DiscoverFilterId.GENRE) }
    )
}

@Composable
private fun sortChip(state: SearchUiState, actions: DiscoverFilterActions) = DiscoverChip(
    id = DiscoverFilterId.SORT,
    key = "sort",
    label = stringResource(R.string.search_filter_sort),
    value = state.sortOption.localizedLabel(),
    icon = Icons.AutoMirrored.Filled.Sort,
    isSet = state.sortOption != SortOption.POPULAR,
    onActivate = { actions.onOpenPanel(DiscoverFilterId.SORT) }
)

@Composable
private fun ratingChip(state: SearchUiState, actions: DiscoverFilterActions) = DiscoverChip(
    id = DiscoverFilterId.RATING,
    key = "rating",
    label = stringResource(R.string.search_filter_rating),
    value = ratingChipValue(state.rating),
    icon = Icons.Default.StarBorder,
    isSet = state.rating.isSet,
    onActivate = { actions.onOpenPanel(DiscoverFilterId.RATING) }
)

@Composable
private fun ratingChipValue(rating: RatingFilter): String {
    val any = stringResource(R.string.search_filter_any)
    val from = rating.min?.let { formatRating(it) } ?: any
    val to = rating.max?.let { formatRating(it) } ?: any
    val range = stringResource(R.string.search_filter_rating_range, from, to)
    return rating.minVotes?.let { "$range · $it+" } ?: range
}

/** "7.0", not "7.0000001" — the value sits on a chip, not in a log line. */
private fun formatRating(value: Double): String = String.format(java.util.Locale.US, "%.1f", value)

@Composable
private fun yearChip(state: SearchUiState, actions: DiscoverFilterActions) = DiscoverChip(
    id = DiscoverFilterId.YEAR,
    key = "year",
    label = stringResource(R.string.search_filter_year),
    value = state.year?.toString(),
    icon = Icons.Default.DateRange,
    isSet = state.year != null,
    onActivate = { actions.onOpenPanel(DiscoverFilterId.YEAR) }
)

@Composable
private fun certificationChip(
    state: SearchUiState,
    certifications: List<String>,
    actions: DiscoverFilterActions
): DiscoverChip {
    // Greyed out rather than gone: TMDB has no certification parameter for series, and a chip
    // that disappears changes the row's length under the user's thumb without explaining why.
    val enabled = supportsCertification(state.selectedType) && certifications.isNotEmpty()
    return DiscoverChip(
        id = DiscoverFilterId.CERTIFICATION,
        key = "certification",
        label = stringResource(R.string.search_filter_age),
        value = state.certification,
        icon = Icons.Default.Security,
        isSet = enabled && state.certification != null,
        isEnabled = enabled,
        onActivate = { if (enabled) actions.onOpenPanel(DiscoverFilterId.CERTIFICATION) }
    )
}

@Composable
private fun hideWatchedChip(state: SearchUiState, actions: DiscoverFilterActions) = DiscoverChip(
    id = DiscoverFilterId.HIDE_WATCHED,
    key = "hidewatched",
    label = stringResource(R.string.search_filter_hide_watched),
    icon = Icons.Default.VisibilityOff,
    // A switch, not a list: there is nothing to choose, so it carries no chevron and no panel.
    hasPanel = false,
    isSet = state.hideWatched,
    onActivate = actions.onToggleHideWatched
)

/** The panel that belongs to [id], or `null` for a chip that is a plain switch. */
@Composable
internal fun filterPanelSpec(
    id: DiscoverFilterId,
    state: SearchUiState,
    certifications: List<String>,
    actions: DiscoverFilterActions
): FilterPanelSpec? = when (id) {
    // The media type is a segmented switch in the row itself, so it has no panel.
    DiscoverFilterId.TYPE -> null
    DiscoverFilterId.GENRE -> genrePanel(state, actions)
    DiscoverFilterId.SORT -> sortPanel(state, actions)
    DiscoverFilterId.RATING -> ratingPanel(state, actions)
    DiscoverFilterId.YEAR -> yearPanel(state, actions)
    DiscoverFilterId.CERTIFICATION -> certificationPanel(state, certifications, actions)
    DiscoverFilterId.HIDE_WATCHED -> null
}

@Composable
private fun genrePanel(state: SearchUiState, actions: DiscoverFilterActions) = FilterPanelSpec(
    id = DiscoverFilterId.GENRE,
    title = stringResource(R.string.search_filter_genres),
    subtitle = state.selectedGenres.size
        .takeIf { it > 0 }
        ?.let { stringResource(R.string.search_filter_selected_count, it) },
    options = genresFor(state.selectedType).map { genre ->
        PanelOption(
            key = "genre_${genre.id}",
            label = genre.localizedNameFor(state.selectedType),
            isSelected = state.selectedGenres.any { it.id == genre.id },
            onToggle = { actions.onToggleGenre(genre) }
        )
    },
    mode = PanelMode(
        leftLabel = stringResource(R.string.search_filter_match_all),
        rightLabel = stringResource(R.string.search_filter_match_any),
        isLeftSelected = state.matchAllGenres,
        onSelect = actions.onMatchAllGenres
    ),
    footer = stringResource(R.string.search_filter_panel_hint)
)

@Composable
private fun sortPanel(state: SearchUiState, actions: DiscoverFilterActions) = FilterPanelSpec(
    id = DiscoverFilterId.SORT,
    title = stringResource(R.string.search_filter_sort),
    options = SortOption.entries.map { sort ->
        PanelOption(
            key = "sort_$sort",
            label = sort.localizedLabel(),
            isSelected = state.sortOption == sort,
            onToggle = { actions.onSelectSort(sort) }
        )
    },
    footer = stringResource(R.string.search_filter_panel_hint)
)

@Composable
private fun ratingPanel(state: SearchUiState, actions: DiscoverFilterActions): FilterPanelSpec {
    val any = stringResource(R.string.search_filter_any)
    val from = ratingOptions(
        prefix = "min", any = any, values = RATING_STEPS, selected = state.rating.min,
        onPick = { actions.onSetRating(state.rating.copy(min = it)) }
    )
    val to = ratingOptions(
        prefix = "max", any = any, values = RATING_CEILINGS, selected = state.rating.max,
        onPick = { actions.onSetRating(state.rating.copy(max = it)) }
    )
    val votes = MIN_VOTE_OPTIONS.map { value ->
        PanelOption(
            key = "votes_$value",
            label = value?.let { "$it+" } ?: any,
            isSelected = state.rating.minVotes == value,
            onToggle = { actions.onSetRating(state.rating.copy(minVotes = value)) }
        )
    }
    return FilterPanelSpec(
        id = DiscoverFilterId.RATING,
        title = stringResource(R.string.search_filter_rating),
        subtitle = stringResource(R.string.search_filter_min_votes),
        options = from + to + votes,
        footer = stringResource(R.string.search_filter_votes_hint)
    )
}

private fun ratingOptions(
    prefix: String,
    any: String,
    values: List<Double>,
    selected: Double?,
    onPick: (Double?) -> Unit
): List<PanelOption> {
    val all: List<Double?> = listOf(null) + values
    return all.map { value ->
        PanelOption(
            key = "${prefix}_$value",
            label = value?.let { formatRating(it) } ?: any,
            isSelected = selected == value,
            onToggle = { onPick(value) }
        )
    }
}

@Composable
private fun yearPanel(state: SearchUiState, actions: DiscoverFilterActions): FilterPanelSpec {
    val any = stringResource(R.string.search_filter_any)
    val currentYear = Calendar.getInstance().get(Calendar.YEAR)
    val years = yearOptions(currentYear)
    val options = listOf(
        PanelOption("year_any", any, state.year == null) { actions.onSelectYear(null) }
    ) + years.map { year ->
        PanelOption(
            key = "year_$year",
            label = year.toString(),
            isSelected = state.year == year,
            onToggle = { actions.onSelectYear(year) }
        )
    }
    return FilterPanelSpec(
        id = DiscoverFilterId.YEAR,
        title = stringResource(R.string.search_filter_year),
        options = options,
        footer = stringResource(R.string.search_filter_panel_hint)
    )
}

@Composable
private fun certificationPanel(
    state: SearchUiState,
    certifications: List<String>,
    actions: DiscoverFilterActions
): FilterPanelSpec {
    val any = stringResource(R.string.search_filter_any)
    val options = listOf(
        PanelOption("cert_any", any, state.certification == null) { actions.onSelectCertification(null) }
    ) + certifications.map { certification ->
        PanelOption(
            key = "cert_$certification",
            label = certification,
            isSelected = state.certification == certification,
            onToggle = { actions.onSelectCertification(certification) }
        )
    }
    return FilterPanelSpec(
        id = DiscoverFilterId.CERTIFICATION,
        title = stringResource(R.string.search_filter_age),
        options = options,
        // The labels are data, not translations: they follow the certification body of the
        // content country, so "12" here is an FSK 12 and a "15" in the UK is a BBFC 15.
        footer = stringResource(R.string.search_filter_age_movies_only)
    )
}
