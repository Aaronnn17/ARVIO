package com.arflix.tv.data.repository

import com.arflix.tv.data.api.AniListApi
import com.arflix.tv.data.api.TmdbApi
import com.arflix.tv.data.api.TvdbApiV4
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNull
import org.junit.Test

class MetadataDispatcherTest {
    @Test
    fun `tvdb series returns null when custom api key is null or empty`() = runBlocking {
        val dispatcher = MetadataDispatcher(
            tmdbApi = mockk<TmdbApi>(relaxed = true),
            aniListApi = mockk<AniListApi>(relaxed = true),
            tvdbApiV4 = mockk<TvdbApiV4>(relaxed = true)
        )

        val resultEmpty = dispatcher.getTvdbSeries(12345, "")
        val resultNull = dispatcher.getTvdbSeries(12345, null)

        assertNull(resultEmpty)
        assertNull(resultNull)
    }
}
