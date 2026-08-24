package com.arflix.tv.ui.screens.player

/** Fonts bundled specifically for subtitle rendering. */
enum class SubtitleFontOption(val preferenceValue: String) {
    SYSTEM("System"),
    NOTO_SANS("Noto Sans"),
    ATKINSON_HYPERLEGIBLE("Atkinson Hyperlegible"),
    LEXEND("Lexend"),
    ROBOTO_CONDENSED("Roboto Condensed");

    companion object {
        const val DefaultPreference = "System"

        fun fromPreference(value: String?): SubtitleFontOption =
            entries.firstOrNull { it.preferenceValue == value } ?: SYSTEM

        fun nextPreference(value: String?): String {
            val current = fromPreference(value)
            return entries[(current.ordinal + 1) % entries.size].preferenceValue
        }
    }
}
