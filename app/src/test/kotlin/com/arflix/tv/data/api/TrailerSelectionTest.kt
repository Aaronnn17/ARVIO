package com.arflix.tv.data.api

import com.arflix.tv.ui.components.forFullHdTrailer
import androidx.media3.common.TrackSelectionParameters
import org.junit.Assert.*
import org.junit.Test

class TrailerSelectionTest {
    @Test fun prefersFullHdWithinOfficialTrailers() {
        val sd = video("sd", 360)
        val hd = video("hd", 1080)
        assertEquals(hd, preferredTrailer(listOf(sd, hd, video("teaser", 2160).copy(type = "Teaser"))))
    }

    @Test fun preservesOfficialAndLanguageResponsePriorityRatherThanPickingUnofficialHd() {
        val official = video("official", 720)
        assertEquals(official, preferredTrailer(listOf(video("unofficial", 1080).copy(official = false), official)))
    }

    @Test fun doesNotLoseTrailersWithoutResolutionMetadata() {
        assertEquals("unknown", preferredTrailer(listOf(video("unknown", 0)))?.key)
        assertNull(preferredTrailer(listOf(video("", 1080), video("other-site", 1080).copy(site = "Vimeo"))))
    }

    @Test fun fullHdAndFourKAreEquivalentSoOriginalOrderIsStable() {
        val hd = video("hd", 1080)
        assertEquals(hd, preferredTrailer(listOf(hd, video("4k", 2160))))
    }

    @Test fun smallViewportDoesNotRestrictNativePreviewButBandwidthCanStillAdapt() {
        val parameters = TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT.buildUpon()
            .setViewportSize(480, 270, true).build().forFullHdTrailer()
        assertEquals(1920, parameters.maxVideoWidth)
        assertEquals(1080, parameters.maxVideoHeight)
        assertEquals(Int.MAX_VALUE, parameters.viewportWidth)
        assertEquals(0, parameters.minVideoHeight)
        assertFalse(parameters.forceHighestSupportedBitrate)
        assertFalse(parameters.forceLowestBitrate)
    }

    private fun video(key: String, height: Int) =
        TmdbVideo(key = key, site = "YouTube", type = "Trailer", official = true, size = height)
}
