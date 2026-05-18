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
    fun xtreamPathsEncodeCredentials() {
        val path = CoreXtreamPaths.movie("https://example.test/", "user name", "p@ss", 42, "mp4")
        assertEquals("https://example.test/movie/user%20name/p%40ss/42.mp4", path)
    }
}
