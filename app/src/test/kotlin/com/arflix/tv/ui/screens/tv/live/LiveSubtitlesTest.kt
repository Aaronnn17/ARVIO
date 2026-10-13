package com.arflix.tv.ui.screens.tv.live

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class LiveSubtitlesTest {
    private fun dvb(language: String?) = Format.Builder()
        .setSampleMimeType(MimeTypes.APPLICATION_DVBSUBS)
        .setLanguage(language)
        .build()

    private fun tracks(vararg subtitles: Pair<String?, Boolean>) = Tracks(subtitles.map { (language, selected) ->
        Tracks.Group(TrackGroup(dvb(language)), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(selected))
    })

    @Test fun preferenceNamesBecomePlayerLanguages() {
        assertEquals("he", subtitlePreferenceLanguage("Hebrew"))
        assertEquals("en", subtitlePreferenceLanguage("English"))
        assertEquals("he", subtitlePreferenceLanguage("heb"))
        assertEquals("ru", subtitlePreferenceLanguage("ru"))
        assertNull(subtitlePreferenceLanguage("Off"))
        assertNull(subtitlePreferenceLanguage(""))
        assertNull(subtitlePreferenceLanguage(null))
    }

    @Test fun optionsListOffThenEachLanguageWithTheSelectionMarked() {
        val options = liveSubtitleOptions(tracks("heb" to true, "rus" to false), offLabel = "Off", displayLocale = Locale.ENGLISH)

        assertEquals(listOf(LIVE_SUBTITLES_OFF, "he", "ru"), options.map { it.key })
        assertEquals(listOf("Off", "Hebrew", "Russian"), options.map { it.label })
        assertEquals(listOf(false, true, false), options.map { it.selected })
    }

    @Test fun offIsSelectedWhenNoSubtitleTrackIsOn() {
        val options = liveSubtitleOptions(tracks("heb" to false, "rus" to false), offLabel = "Off", displayLocale = Locale.ENGLISH)
        assertTrue(options.first().selected)
    }

    @Test fun aStreamWithoutSubtitlesOffersNothing() {
        assertTrue(liveSubtitleOptions(Tracks.EMPTY, offLabel = "Off").isEmpty())
    }

    @Test fun audioPreferenceAutoMeansNoPreference() {
        assertNull(audioPreferenceLanguage("Auto (Original)"))
        assertNull(audioPreferenceLanguage(null))
        assertEquals("he", audioPreferenceLanguage("Hebrew"))
        assertEquals("ru", audioPreferenceLanguage("Russian"))
    }

    @Test fun audioOptionsListEachLanguageWithoutAnOffEntry() {
        val audio = Tracks(listOf("eng" to true, "rus" to false).map { (language, selected) ->
            Tracks.Group(
                TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).setLanguage(language).build()),
                false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(selected)
            )
        })

        val options = liveAudioOptions(audio, displayLocale = Locale.ENGLISH)

        assertEquals(listOf("en", "ru"), options.map { it.key })
        assertEquals(listOf("English", "Russian"), options.map { it.label })
        assertEquals(listOf(true, false), options.map { it.selected })
        assertTrue(liveSubtitleOptions(audio, offLabel = "Off").isEmpty())
    }

    @Test fun tracksWithoutALanguageStillGetAnEntry() {
        val options = liveSubtitleOptions(tracks(null to false, null to false), offLabel = "Off", displayLocale = Locale.ENGLISH)
        assertEquals(3, options.size)
        assertEquals(2, options.drop(1).map { it.key }.distinct().size)
    }
}
