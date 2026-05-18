package com.arvio.shared

import kotlinx.serialization.Serializable

@Serializable
data class CoreMediaItem(
    val tmdbId: Int? = null,
    val imdbId: String? = null,
    val title: String,
    val year: String = "",
    val type: CoreMediaType = CoreMediaType.Movie,
    val season: Int? = null,
    val episode: Int? = null,
)

@Serializable
enum class CoreMediaType {
    Movie,
    Series,
}

@Serializable
data class CoreResolvedStream(
    val addonId: String? = null,
    val addonName: String,
    val sourceName: String,
    val title: String,
    val quality: String = "",
    val sizeBytes: Long = 0,
    val languageHint: String = "",
    val cached: Boolean = false,
    val directPlayable: Boolean = true,
)

object CoreTitleMatcher {
    fun normalize(value: String): String {
        return value
            .lowercase()
            .map { if (it.isLetterOrDigit()) it else ' ' }
            .joinToString(separator = "")
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() && it !in ignoredArticles }
            .joinToString(" ")
    }

    fun score(candidateTitle: String, candidateYear: String?, item: CoreMediaItem): Int {
        val candidate = normalize(candidateTitle)
        val expected = normalize(item.title)
        var score = when {
            candidate == expected -> 90
            candidate.contains(expected) || expected.contains(candidate) -> 55
            else -> {
                val candidateTokens = candidate.split(' ').filter { it.length > 2 }.toSet()
                val expectedTokens = expected.split(' ').filter { it.length > 2 }.toSet()
                (candidateTokens intersect expectedTokens).size.coerceAtMost(3) * 15
            }
        }
        val itemYear = item.year.onlyDigits()
        val matchYear = candidateYear?.onlyDigits().orEmpty()
        if (itemYear.isNotBlank() && itemYear == matchYear) {
            score += 25
        } else if (itemYear.isNotBlank() && candidateTitle.contains(itemYear)) {
            score += 15
        }
        return score
    }

    private val ignoredArticles = setOf("the", "a", "an")
}

object CoreStreamRanker {
    fun qualityRank(quality: String): Int {
        val value = quality.lowercase()
        return when {
            "2160" in value || "4k" in value || "uhd" in value -> 4
            "1080" in value || "fhd" in value -> 3
            "720" in value || "hd" in value -> 2
            "480" in value || "sd" in value -> 1
            else -> 0
        }
    }

    fun sort(streams: List<CoreResolvedStream>, preferredLanguage: String = ""): List<CoreResolvedStream> {
        val preferred = preferredLanguage.lowercase().takeIf { it.isNotBlank() }
        return streams.sortedWith(
            compareByDescending<CoreResolvedStream> { it.directPlayable }
                .thenByDescending { qualityRank(it.quality) }
                .thenByDescending { it.sizeBytes }
                .thenByDescending { if (preferred != null && it.languageHint.lowercase().contains(preferred)) 1 else 0 }
                .thenByDescending { it.cached }
        )
    }
}

object CoreXtreamPaths {
    fun live(baseUrl: String, username: String, password: String, streamId: Int): String {
        return "${baseUrl.trimEnd('/')}/live/${username.pathSegment()}/${password.pathSegment()}/$streamId.ts"
    }

    fun movie(baseUrl: String, username: String, password: String, streamId: Int, extension: String): String {
        return "${baseUrl.trimEnd('/')}/movie/${username.pathSegment()}/${password.pathSegment()}/$streamId.${extension.pathSegment()}"
    }

    fun series(baseUrl: String, username: String, password: String, episodeId: String, extension: String): String {
        return "${baseUrl.trimEnd('/')}/series/${username.pathSegment()}/${password.pathSegment()}/${episodeId.pathSegment()}.${extension.pathSegment()}"
    }
}

private fun String.onlyDigits(): String = filter { it.isDigit() }

private fun String.pathSegment(): String {
    return encodeToByteArray().joinToString("") { byte ->
        val value = byte.toInt() and 0xff
        val char = value.toChar()
        if (char.isLetterOrDigit() || char in "-._~") {
            char.toString()
        } else {
            "%${value.toString(16).uppercase().padStart(2, '0')}"
        }
    }
}
