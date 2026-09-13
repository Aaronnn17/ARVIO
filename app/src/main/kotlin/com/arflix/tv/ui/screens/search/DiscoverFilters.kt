package com.arflix.tv.ui.screens.search

import com.arflix.tv.util.ContentRating

/** The seven controls of the discover row, in the order the approved design shows them. */
enum class DiscoverFilterId { TYPE, GENRE, SORT, RATING, YEAR, CERTIFICATION, HIDE_WATCHED }

/**
 * Rating range plus the vote floor, the three values that share one panel.
 *
 * The floor defaults to "any": a high floor is the usual way a discover page quietly loses
 * every new release, because a title released last week has not collected the votes yet.
 */
data class RatingFilter(
    val min: Double? = null,
    val max: Double? = null,
    val minVotes: Int? = null
) {
    val isSet: Boolean get() = min != null || max != null || minVotes != null
}

/** Vote floors offered in the rating panel. `null` is "any" and stays the default. */
val MIN_VOTE_OPTIONS: List<Int?> = listOf(null, 50, 100, 500, 1000)

/**
 * Age certifications offered per country.
 *
 * TMDB filters certifications for movies only — `discover/tv` has no equivalent parameter — and
 * the values are country-specific strings, not a scale, so they cannot be derived. Only
 * countries whose list is short and stable are offered; everywhere else the chip stays off.
 */
val CERTIFICATIONS: Map<String, List<String>> = mapOf(
    "US" to listOf("G", "PG", "PG-13", "R", "NC-17"),
    "DE" to listOf("0", "6", "12", "16", "18"),
    "GB" to listOf("U", "PG", "12A", "15", "18"),
    "FR" to listOf("U", "10", "12", "16", "18"),
    "NL" to listOf("AL", "6", "9", "12", "16")
)

/**
 * Genres as TMDB wants them in `with_genres`.
 *
 * The separator is the whole of E3: a comma means AND (only titles carrying every chosen
 * genre), a pipe means OR. AND is the default because it is TMDB's own and because the user
 * decided the same way in his own app.
 */
fun genresParam(genres: List<Genre>, matchAll: Boolean): String? {
    if (genres.isEmpty()) return null
    val separator = if (matchAll) "," else "|"
    return genres.joinToString(separator) { it.id.toString() }
}

/**
 * The genre list offered for a media type — the same lists the rows have always used, so the
 * panel can never offer a genre the following request would drop.
 */
fun genresFor(type: DiscoverType): List<Genre> = when (type) {
    DiscoverType.MOVIES -> MOVIE_GENRES
    DiscoverType.TV_SHOWS -> TV_GENRES
    DiscoverType.ANIME -> ANIME_GENRES
    DiscoverType.ALL -> ALL_GENRES
}

/**
 * Keeps only the genres that exist for [type].
 *
 * Switching Movies → Series used to drop the genre entirely, because ids differ per media type
 * ("Action" is 28 for a film, "Action & Adventure" 10759 for a series) and a genre carried over
 * blindly returns an empty list. Remapping first and dropping only what has no counterpart keeps
 * the chosen genre wherever one exists, which is all the user ever noticed about it.
 */
fun remapGenresForType(genres: List<Genre>, type: DiscoverType): List<Genre> {
    if (genres.isEmpty()) return genres
    val available = genresFor(type)
    return genres.mapNotNull { genre ->
        val mappedId = remapGenreId(genre.id, type)
        available.firstOrNull { it.id == mappedId }
    }.distinctBy { it.id }
}

/**
 * One genre id translated into [type]'s numbering. Ids that mean the same thing in both
 * numberings (Comedy 35, Drama 18, …) are returned unchanged.
 */
fun remapGenreId(genreId: Int, type: DiscoverType): Int = when (type) {
    DiscoverType.TV_SHOWS -> when (genreId) {
        28, 12 -> 10759          // Action, Adventure -> Action & Adventure
        14, 878 -> 10765         // Fantasy, Sci-Fi   -> Sci-Fi & Fantasy
        10752 -> 10768           // War               -> War & Politics
        else -> genreId
    }
    // Anime is a series request, but ANIME_GENRES is written in the movie numbering and is
    // translated to the series one later, on the way to TMDB. Numbering-wise it belongs here.
    DiscoverType.MOVIES, DiscoverType.ANIME -> when (genreId) {
        10759 -> 28
        10765 -> 878
        10768 -> 10752
        10762 -> 10751           // Kids -> Family
        else -> genreId
    }
    DiscoverType.ALL -> genreId
}

/** Years offered in the year panel, newest first. TMDB has nothing usable before this. */
fun yearOptions(currentYear: Int, oldest: Int = 1950): List<Int> =
    (currentYear downTo oldest).toList()

/**
 * The certification list for the profile's content language, or empty when that country has
 * none we can offer. An empty list is what greys the age chip out.
 */
fun certificationsForLanguage(contentLanguage: String?): List<String> =
    CERTIFICATIONS[ContentRating.regionOf(contentLanguage)].orEmpty()

/**
 * Whether a media type can be filtered by age at all.
 *
 * TMDB offers `certification.lte` under `discover/movie` only. The chip therefore stays in
 * place and greys out for series instead of disappearing — a control that vanishes reads as a
 * bug, one that greys out reads as an answer.
 */
fun supportsCertification(type: DiscoverType): Boolean = type == DiscoverType.MOVIES

/** Leaving the panel upwards, back to the chip that opened it. */
const val PANEL_FOCUS_LEAVE = -1

/**
 * Where the focus lands inside an open filter panel after a direction key.
 *
 * The panel is a grid of options with [columns] per row. Sideways movement stays inside its
 * row, so the focus cannot jump from the end of one line to the start of the next — on a
 * remote that reads as the selection teleporting. Up from the first row leaves the panel
 * ([PANEL_FOCUS_LEAVE]); down from the last row stays put rather than closing, because a
 * closing panel is not what "further down the list" means.
 */
fun movePanelFocus(index: Int, count: Int, columns: Int, dx: Int, dy: Int): Int {
    if (count <= 0) return PANEL_FOCUS_LEAVE
    val safeColumns = columns.coerceAtLeast(1)
    val current = index.coerceIn(0, count - 1)
    if (dy != 0) {
        val row = current / safeColumns
        if (dy < 0 && row == 0) return PANEL_FOCUS_LEAVE
        val target = current + dy * safeColumns
        return if (target in 0 until count) target else current
    }
    if (dx != 0) {
        val row = current / safeColumns
        val target = current + dx
        val targetRow = target / safeColumns
        return if (target in 0 until count && targetRow == row) target else current
    }
    return current
}
