package com.arvio.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ArvioCoreTest {
    @Test
    fun titleMatcherNormalizesArticlesAndPunctuation() {
        val item = CoreMediaItem(title = "The Last of Us", year = "2023", type = CoreMediaType.Series)
        assertTrue(CoreTitleMatcher.score("Last.of.Us.S01E01.2023.1080p", "2023", item) >= 70)
    }

    @Test
    fun streamRankerPrefersPlayableHighQualityStreams() {
        val sorted = CoreStreamRanker.sort(
            listOf(
                CoreResolvedStream(addonName = "A", sourceName = "A", title = "A", quality = "720p"),
                CoreResolvedStream(addonName = "B", sourceName = "B", title = "B", quality = "4K", sizeBytes = 10),
            )
        )
        assertEquals("B", sorted.first().addonName)
    }

    @Test
    fun streamRankerParsesSizeAndScoresLanguage() {
        assertEquals(2_147_483_648L, CoreStreamRanker.parseSizeBytes("Movie 2 GB 1080p"))
        val englishScore = CoreStreamRanker.sourceScore(
            quality = "1080p",
            size = "2 GB",
            addonName = "Addon",
            sourceName = "English",
            title = "Movie",
            isPlayable = true,
            preferredLanguage = "English",
            cached = true,
        )
        val otherScore = CoreStreamRanker.sourceScore(
            quality = "720p",
            size = "1 GB",
            addonName = "Addon",
            sourceName = "French",
            title = "Movie",
            isPlayable = true,
            preferredLanguage = "English",
            cached = false,
        )
        assertTrue(englishScore > otherScore)
    }

    @Test
    fun m3uParserExtractsAttributesAndName() {
        val line = """#EXTINF:-1 tvg-name="BBC One" group-title="UK",BBC One HD"""
        assertEquals("BBC One", CoreM3uParser.attribute(line, "tvg-name"))
        assertEquals("UK", CoreM3uParser.attribute(line, "group-title"))
        assertEquals("BBC One", CoreM3uParser.displayName(line))
    }

    @Test
    fun vodMatcherUsesExternalIdsAndTitleFallback() {
        val exact = CoreVodMatcher.score(
            candidateTitle = "Different Name",
            candidateYear = "2023",
            candidateTmdb = "100",
            candidateImdb = "tt123",
            itemTmdb = 100,
            itemImdb = "tt123",
            itemTitle = "Expected",
            itemYear = "2023",
        )
        val title = CoreVodMatcher.score(
            candidateTitle = "Expected 2023 1080p",
            candidateYear = "2023",
            candidateTmdb = null,
            candidateImdb = null,
            itemTmdb = 100,
            itemImdb = "tt123",
            itemTitle = "Expected",
            itemYear = "2023",
        )
        assertTrue(exact > title)
        assertTrue(CoreVodMatcher.isUsableMatch(title))
        assertEquals(listOf("1", "01"), CoreVodMatcher.episodeSeasonKeys(1))
    }

    @Test
    fun playbackProgressRulesMatchAppThresholds() {
        assertEquals(0.5, CorePlaybackProgress.fraction(50, 100))
        assertEquals(0.5, CorePlaybackProgress.percentFraction(50.0))
        assertTrue(CorePlaybackProgress.shouldSave(6, 31))
        assertTrue(CorePlaybackProgress.shouldMarkWatched(90, 100))
        assertTrue(CorePlaybackProgress.shouldShowContinueWatching(0.5))
        assertEquals("tv-123-1-2", CorePlaybackProgress.historyKey("tv", 123, 1, 2))
    }

    @Test
    fun xtreamPathsEncodeCredentials() {
        val path = CoreXtreamPaths.movie("https://example.test/", "user name", "p@ss", 42, "mp4")
        assertEquals("https://example.test/movie/user%20name/p%40ss/42.mp4", path)
    }
}
