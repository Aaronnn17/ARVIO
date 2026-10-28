package com.arflix.tv.ui.components

import com.arflix.tv.data.model.StreamBehaviorHints
import com.arflix.tv.data.model.StreamSource
import com.arflix.tv.data.model.Subtitle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StreamPresentationLanguageTest {
    @Test fun subtitleSectionNeverChangesTheAdvertisedAudio() {
        val result = presentation(source(description = "Audio: English\nSubtitles: German French"), "fr")
        assertEquals("🇬🇧 EN", field(result, "languageBadge"))
        assertEquals("EN", field(result, "languageLabel"))
    }

    @Test fun subtitleOnlyMetadataDoesNotReappearThroughLegacyFallbacks() {
        val stream = source(description = "Subtitles: French German").copy(
            subtitles = listOf(Subtitle("fr", "https://example.invalid/sub.vtt", "fr", "French"))
        )
        val result = presentation(stream, "fr")
        assertNull(field(result, "languageBadge"))
        assertNull(field(result, "languageLabel"))
    }

    @Test fun subtitleSectionDoesNotHideTheAudioInAnotherField() {
        val result = presentation(source(
            description = "Subtitles: French German",
            hints = StreamBehaviorHints(filename = "Film.ENG.1080p.mkv")
        ), "fr")
        assertEquals("🇬🇧 EN", field(result, "languageBadge"))
    }

    @Test fun indianFlagDoesNotAdvertiseAnUnlistedHindiTrack() {
        assertEquals("TA", field(presentation(source(description = "🇮🇳 Tamil"), "hi"), "languageBadge"))
        assertEquals("TE", field(presentation(source(description = "🇮🇳 Telugu"), "hi"), "languageBadge"))
    }

    @Test fun explicitAudioHintStillWorksWhenOnlySubtitlesAreNamedInTheDescription() {
        val result = presentation(source(
            description = "Subtitles: French German",
            hints = StreamBehaviorHints(language = "en")
        ), "fr")
        assertEquals("🇬🇧 EN", field(result, "languageBadge"))
    }

    @Test fun aLanguageWordInTheMovieTitleDoesNotReappearThroughTheOldRegex() {
        val result = presentation(source().copy(source = "The.Italian.Job.2003.1080p.mkv"), "it", "The Italian Job")
        assertNull(field(result, "languageBadge"))
        assertNull(field(result, "languageLabel"))
    }

    private fun source(description: String? = null, hints: StreamBehaviorHints? = null) = StreamSource(
        source = "Film.1080p.WEB-DL",
        addonName = "AIOStreams",
        quality = "1080p",
        size = "1 GB",
        description = description,
        behaviorHints = hints
    )

    private fun presentation(stream: StreamSource, preferred: String, title: String = "Film"): Any {
        val method = Class.forName("com.arflix.tv.ui.components.StreamSelectorKt").getDeclaredMethod(
            "presentSource", StreamSource::class.java, String::class.java, String::class.java, String::class.java
        )
        method.isAccessible = true
        return method.invoke(null, stream, "Unknown", preferred, title)!!
    }

    private fun field(result: Any, name: String): Any? = result.javaClass.getDeclaredField(name).run {
        isAccessible = true
        get(result)
    }
}
