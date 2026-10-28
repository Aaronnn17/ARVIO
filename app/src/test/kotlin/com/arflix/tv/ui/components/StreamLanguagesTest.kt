package com.arflix.tv.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StreamLanguagesTest {
    @Test
    fun `every named language is found in order`() {
        assertEquals(listOf("en", "de", "it"), detectStreamLanguages("4K WEB-DL | Eng Deu Ita | 20 Mbps"))
    }

    @Test
    fun `scene separators and full names count`() {
        assertEquals(listOf("de", "en"), detectStreamLanguages("Film.2024.German.DL.ENG.2160p.WEB.h265"))
        assertEquals(listOf("de"), detectStreamLanguages("Deutsch AC3"))
    }

    @Test
    fun `flag emoji count`() {
        assertEquals(listOf("en", "de"), detectStreamLanguages("🇬🇧 / 🇩🇪 · 8 GB"))
    }

    @Test
    fun `two letter words are not languages`() {
        assertEquals(emptyList<String>(), detectStreamLanguages("IT 2017 DE LA SOUL 1080p"))
    }

    @Test
    fun `preferred language leads the badge with the others counted`() {
        assertEquals("🇩🇪 DE +2", streamLanguageBadge(listOf("en", "de", "it"), false, "de"))
        assertEquals("🇬🇧 EN +2", streamLanguageBadge(listOf("en", "de", "it"), false, "fr"))
        assertEquals("🇩🇪 DE +1", streamLanguageBadge(listOf("en", "de"), false, "German"))
    }

    @Test
    fun `single language and multi audio`() {
        assertEquals("🇩🇪 DE", streamLanguageBadge(listOf("de"), false, "de"))
        assertEquals("🌐 DE", streamLanguageBadge(listOf("de"), true, "de"))
        assertNull(streamLanguageBadge(emptyList(), true, "de"))
    }

    @Test
    fun `language without a flag shows its code`() {
        assertEquals("TE +1", streamLanguageBadge(listOf("te", "en"), false, null))
    }

    @Test
    fun `back to back flags are read pair by pair`() {
        assertEquals(listOf("en", "ru"), detectStreamLanguages("🇬🇧🇷🇺"))
        assertEquals(listOf("en", "de", "it", "hu"), detectStreamLanguages("🇺🇸🇩🇪🇮🇹🇭🇺"))
    }

    @Test
    fun `title words and subtitle languages are not audio`() {
        assertEquals(listOf("en"), detectStreamLanguages("The.Italian.Job.2003.ENG.1080p", ignoreWordsOf = "The Italian Job"))
        assertEquals(listOf("en"), detectStreamLanguages("Film.2024.ENG.GERMAN.SUBBED.1080p"))
    }

    @Test
    fun `brazilian portuguese preference ranks portuguese first`() {
        assertEquals("🇵🇹 PT +1", streamLanguageBadge(listOf("en", "pt"), false, "Portuguese (Brazil)"))
    }
}
