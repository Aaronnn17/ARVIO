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
    fun xtreamPathsEncodeCredentials() {
        val path = CoreXtreamPaths.movie("https://example.test/", "user name", "p@ss", 42, "mp4")
        assertEquals("https://example.test/movie/user%20name/p%40ss/42.mp4", path)
    }
}
