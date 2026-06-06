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
    fun qualityLabel(text: String): String {
        return when (qualityRank(text)) {
            4 -> "4K"
            3 -> "1080p"
            2 -> "720p"
            1 -> "480p"
            else -> "Direct"
        }
    }

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

    fun parseSizeBytes(text: String): Long {
        val match = Regex("""(?i)(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB)""").find(text) ?: return 0
        val amount = match.groupValues.getOrNull(1)?.toDoubleOrNull() ?: return 0
        val unit = match.groupValues.getOrNull(2)?.uppercase().orEmpty()
        val multiplier = when (unit) {
            "TB" -> 1_099_511_627_776.0
            "GB" -> 1_073_741_824.0
            "MB" -> 1_048_576.0
            "KB" -> 1024.0
            else -> 1.0
        }
        return (amount * multiplier).toLong()
    }

    fun sourceScore(
        quality: String,
        size: String,
        addonName: String,
        sourceName: String,
        title: String,
        isPlayable: Boolean,
        preferredLanguage: String = "",
        cached: Boolean = false,
    ): Int {
        val text = listOf(addonName, sourceName, title).joinToString(" ")
        val languageScore = languageScore(text, preferredLanguage)
        return (if (isPlayable) 100_000 else 0) +
            (qualityRank(quality) * 10_000) +
            ((parseSizeBytes(size) / 1_073_741_824L).coerceAtMost(99) * 100).toInt() +
            (languageScore * 40) +
            if (cached) 20 else 0
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

    private fun languageScore(text: String, preferredLanguage: String): Int {
        val preferred = normalizeLanguage(preferredLanguage).ifBlank { return 0 }
        val codes = extractLanguageCodes(text)
        val lower = text.lowercase()
        return when {
            preferred in codes -> 2
            codes.isEmpty() || "multi" in lower || "dual" in lower -> 1
            else -> 0
        }
    }

    private fun normalizeLanguage(value: String): String {
        return when (value.trim().lowercase()) {
            "english", "eng" -> "en"
            "dutch", "nederlands", "nl" -> "nl"
            "spanish", "espanol", "español" -> "es"
            "french", "francais", "français" -> "fr"
            "german", "deutsch" -> "de"
            else -> value.trim().lowercase().take(2)
        }
    }

    private fun extractLanguageCodes(text: String): Set<String> {
        val lower = text.lowercase()
        val direct = setOf("en", "nl", "es", "fr", "de", "it", "pt", "ja", "ko")
            .filter { Regex("""(^|[^a-z])$it([^a-z]|$)""").containsMatchIn(lower) }
            .toSet()
        val names = buildSet {
            if ("english" in lower || " eng " in " $lower ") add("en")
            if ("dutch" in lower || "nederlands" in lower) add("nl")
            if ("spanish" in lower || "espanol" in lower || "español" in lower) add("es")
            if ("french" in lower || "francais" in lower || "français" in lower) add("fr")
            if ("german" in lower || "deutsch" in lower) add("de")
        }
        return direct + names
    }
}

object CoreXtreamPaths {
    fun live(baseUrl: String, username: String, password: String, streamId: Int): String {
        return "${baseUrl.trimEnd('/')}/live/${username.pathSegment()}/${password.pathSegment()}/$streamId.ts"
    }

    fun movie(baseUrl: String, username: String, password: String, streamId: Int, fileExtension: String): String {
        return "${baseUrl.trimEnd('/')}/movie/${username.pathSegment()}/${password.pathSegment()}/$streamId.${fileExtension.pathSegment()}"
    }

    fun series(baseUrl: String, username: String, password: String, episodeId: String, fileExtension: String): String {
        return "${baseUrl.trimEnd('/')}/series/${username.pathSegment()}/${password.pathSegment()}/${episodeId.pathSegment()}.${fileExtension.pathSegment()}"
    }
}

object CoreVodMatcher {
    fun scoreValue(
        candidateTitle: String,
        candidateYear: String,
        candidateTmdb: String,
        candidateImdb: String,
        itemTmdb: Int,
        itemImdb: String,
        itemTitle: String,
        itemYear: String,
    ): Int {
        return score(
            candidateTitle = candidateTitle,
            candidateYear = candidateYear.takeIf { it.isNotBlank() },
            candidateTmdb = candidateTmdb.takeIf { it.isNotBlank() },
            candidateImdb = candidateImdb.takeIf { it.isNotBlank() },
            itemTmdb = itemTmdb.takeIf { it > 0 },
            itemImdb = itemImdb.takeIf { it.isNotBlank() },
            itemTitle = itemTitle,
            itemYear = itemYear,
        )
    }

    fun score(
        candidateTitle: String,
        candidateYear: String?,
        candidateTmdb: String?,
        candidateImdb: String?,
        itemTmdb: Int?,
        itemImdb: String?,
        itemTitle: String,
        itemYear: String,
    ): Int {
        var score = 0
        if (itemTmdb != null && candidateTmdb?.onlyDigits().orEmpty() == itemTmdb.toString()) {
            score += 140
        }
        val normalizedCandidateImdb = candidateImdb?.trim()?.lowercase().orEmpty()
        val normalizedItemImdb = itemImdb?.trim()?.lowercase().orEmpty()
        if (normalizedItemImdb.isNotBlank() && normalizedCandidateImdb == normalizedItemImdb) {
            score += 140
        }
        score += CoreTitleMatcher.score(
            candidateTitle = candidateTitle,
            candidateYear = candidateYear,
            item = CoreMediaItem(
                tmdbId = itemTmdb,
                imdbId = itemImdb,
                title = itemTitle,
                year = itemYear,
            )
        )
        return score
    }

    fun isUsableMatch(score: Int): Boolean = score >= 70

    fun seasonKey(season: Int): String = season.toString()

    fun paddedSeasonKey(season: Int): String = season.toString().padStart(2, '0')

    fun episodeSeasonKeys(season: Int): List<String> {
        return listOf(seasonKey(season), paddedSeasonKey(season)).distinct()
    }
}

object CorePlaybackProgress {
    fun fraction(positionSeconds: Int, durationSeconds: Int): Double {
        if (positionSeconds <= 0 || durationSeconds <= 0) return 0.0
        return (positionSeconds.toDouble() / durationSeconds.toDouble()).coerceIn(0.0, 1.0)
    }

    fun percentFraction(percent: Double): Double {
        return (percent / 100.0).coerceIn(0.0, 1.0)
    }

    fun shouldSave(positionSeconds: Int, durationSeconds: Int): Boolean {
        return positionSeconds > 5 && durationSeconds > 30
    }

    fun shouldMarkWatched(positionSeconds: Int, durationSeconds: Int): Boolean {
        return fraction(positionSeconds, durationSeconds) >= 0.9
    }

    fun shouldShowContinueWatching(progressFraction: Double): Boolean {
        return progressFraction > 0.0 && progressFraction < 0.9
    }

    fun historyKey(mediaType: String, tmdbId: Int, season: Int?, episode: Int?): String {
        return "${mediaType.lowercase()}-$tmdbId-${season ?: 0}-${episode ?: 0}"
    }

    fun historyKeyValue(mediaType: String, tmdbId: Int, season: Int, episode: Int): String {
        return historyKey(mediaType, tmdbId, season.takeIf { it > 0 }, episode.takeIf { it > 0 })
    }
}

object CoreM3uParser {
    fun attribute(line: String, key: String): String? {
        val pattern = Regex("""([A-Za-z0-9_-]+)="([^"]*)"""")
        return pattern.findAll(line)
            .firstOrNull { it.groupValues.getOrNull(1)?.equals(key, ignoreCase = true) == true }
            ?.groupValues
            ?.getOrNull(2)
            ?.trim()
            ?.takeIf { it.isNotBlank() }
    }

    fun displayName(line: String): String {
        return attribute(line, "tvg-name")
            ?: line.substringAfter(',', missingDelimiterValue = "")
                .trim()
                .takeIf { it.isNotBlank() }
            ?: "Channel"
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
