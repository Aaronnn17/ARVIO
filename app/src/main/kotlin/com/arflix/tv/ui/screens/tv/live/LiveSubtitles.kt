package com.arflix.tv.ui.screens.tv.live

import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import java.util.Locale

/**
 * Subtitle and audio choices on live channels. Channels often carry their subtitles inside the
 * stream (DVB bitmap subtitles in MPEG-TS, one track per language) and more than one audio
 * language. Nothing on the Live TV screen used to choose between them, so subtitles only showed
 * when the device's system captions happened to be on in the same language, and the audio was
 * whatever the stream listed first.
 */

/** "off" (subtitles only), or a track's normalized language (or its position when it has none). */
internal const val LIVE_SUBTITLES_OFF = "off"

internal data class LiveSubtitleOption(
    val key: String,
    val label: String,
    val selected: Boolean,
)

/**
 * The profile's "Default subtitle" setting as a language for the player ("Hebrew" -> "he"),
 * or null when subtitles are switched off there.
 */
internal fun subtitlePreferenceLanguage(preference: String?): String? {
    val value = preference?.trim().orEmpty()
    if (value.isBlank() || value.lowercase(Locale.ROOT) in DISABLED_PREFERENCES) return null
    return languageFromPreference(value)
}

/** The profile's "Default audio language" setting, or null for "Auto (Original)". */
internal fun audioPreferenceLanguage(preference: String?): String? {
    val value = preference?.trim().orEmpty()
    if (value.isBlank() || value.lowercase(Locale.ROOT).startsWith("auto") ||
        value.lowercase(Locale.ROOT).startsWith("original")
    ) return null
    return languageFromPreference(value)
}

/** The subtitle choices for what is playing: "Off" first, then one per language or track. */
internal fun liveSubtitleOptions(tracks: Tracks, offLabel: String, displayLocale: Locale = Locale.getDefault()) =
    liveTrackOptions(tracks, C.TRACK_TYPE_TEXT, offLabel, displayLocale)

/** The audio choices for what is playing, one per language or track. */
internal fun liveAudioOptions(tracks: Tracks, displayLocale: Locale = Locale.getDefault()) =
    liveTrackOptions(tracks, C.TRACK_TYPE_AUDIO, offLabel = null, displayLocale)

/** Applies a choice from [liveSubtitleOptions]; false when that track is not in this stream. */
internal fun applyLiveSubtitleChoice(player: Player, key: String): Boolean =
    applyLiveTrackChoice(player, C.TRACK_TYPE_TEXT, key)

/** Applies a choice from [liveAudioOptions]; false when that track is not in this stream. */
internal fun applyLiveAudioChoice(player: Player, key: String): Boolean =
    applyLiveTrackChoice(player, C.TRACK_TYPE_AUDIO, key)

/** Back to automatic subtitle selection: the preferred language, if the profile has one. */
internal fun resetLiveSubtitleChoice(player: Player, preferredLanguage: String?) {
    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        .apply { if (preferredLanguage != null) setPreferredTextLanguages(preferredLanguage) }
        .build()
}

/** Back to automatic audio selection: the preferred language, if the profile has one. */
internal fun resetLiveAudioChoice(player: Player, preferredLanguage: String?) {
    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
        .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
        .apply { if (preferredLanguage != null) setPreferredAudioLanguages(preferredLanguage) }
        .build()
}

private fun liveTrackOptions(tracks: Tracks, type: Int, offLabel: String?, displayLocale: Locale): List<LiveSubtitleOption> {
    val list = typedTracks(tracks, type)
    if (list.isEmpty()) return emptyList()
    val options = mutableListOf<LiveSubtitleOption>()
    if (offLabel != null) {
        options += LiveSubtitleOption(LIVE_SUBTITLES_OFF, offLabel, selected = list.none { it.selected })
    }
    list.distinctBy { it.key }.forEach { track ->
        options += LiveSubtitleOption(track.key, track.label(displayLocale), selected = list.any { it.key == track.key && it.selected })
    }
    return options
}

private fun applyLiveTrackChoice(player: Player, type: Int, key: String): Boolean {
    val builder = player.trackSelectionParameters.buildUpon().clearOverridesOfType(type)
    if (key == LIVE_SUBTITLES_OFF && type == C.TRACK_TYPE_TEXT) {
        player.trackSelectionParameters = builder.setTrackTypeDisabled(type, true).build()
        return true
    }
    val track = typedTracks(player.currentTracks, type).firstOrNull { it.key == key } ?: return false
    player.trackSelectionParameters = builder
        .setTrackTypeDisabled(type, false)
        .addOverride(TrackSelectionOverride(track.group.mediaTrackGroup, track.trackIndex))
        .build()
    return true
}

private class LiveTrack(
    val group: Tracks.Group,
    val trackIndex: Int,
    val key: String,
    val language: String?,
    val name: String?,
    val selected: Boolean,
    val position: Int,
) {
    fun label(displayLocale: Locale): String {
        val languageName = language
            ?.let { Locale.forLanguageTag(it).getDisplayLanguage(displayLocale) }
            ?.takeIf { it.isNotBlank() && !it.equals(language, ignoreCase = true) }
            ?.replaceFirstChar { it.titlecase(displayLocale) }
        return listOfNotNull(languageName ?: language, name?.takeIf { it.isNotBlank() && it != languageName })
            .joinToString(" · ")
            .ifBlank { "#$position" }
    }
}

private fun typedTracks(tracks: Tracks, type: Int): List<LiveTrack> = buildList {
    var position = 0
    tracks.groups.filter { it.type == type }.forEach { group ->
        for (i in 0 until group.length) {
            position++
            if (!group.isTrackSupported(i)) continue
            val format = group.getTrackFormat(i)
            val language = format.language?.takeIf { it.isNotBlank() && it != C.LANGUAGE_UNDETERMINED }
                ?.let(::normalizeLanguage)
            add(LiveTrack(group, i, language ?: "track$position", language, format.label, group.isTrackSelected(i), position))
        }
    }
}

private fun languageFromPreference(value: String): String? {
    if (value.length in 2..3 && value.all(Char::isLetter)) return normalizeLanguage(value)
    val byName = Locale.getAvailableLocales().firstOrNull {
        it.getDisplayLanguage(Locale.ENGLISH).equals(value, ignoreCase = true)
    } ?: return null
    return normalizeLanguage(byName.language)
}

/** ISO 639-2 and legacy codes to the two-letter form the player uses ("heb", "iw" -> "he"). */
private fun normalizeLanguage(code: String): String {
    val lower = code.lowercase(Locale.ROOT)
    if (lower == "iw" || lower == "heb") return "he"
    if (lower.length == 3) {
        Locale.getISOLanguages().firstOrNull { Locale(it).isO3Language == lower }?.let { return it }
    }
    return lower
}

private val DISABLED_PREFERENCES = setOf("off", "none", "no subtitles", "disabled")
