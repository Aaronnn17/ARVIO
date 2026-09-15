package com.arflix.tv.ui.screens.search

/**
 * Why the search screen must not start in typing mode, and what decides it.
 *
 * The screen is opened with a select press. On a TV that same press is still travelling when
 * the new screen has already taken the focus, so it lands a second time — on the search bar,
 * where select means "start typing". Typing mode then stands up without a keyboard behind it:
 * the text field was not attached yet when the keyboard was asked for. What the user sees is a
 * ring in the search bar, no keyboard, and every direction key swallowed by an input that isn't
 * there; only BACK gets out. Reported twice from a device, reproduced by the user.
 *
 * The window itself was already opened on entry ([SEARCH_SELECT_SUPPRESS_MS] after the screen
 * comes up) but never asked about — this function is the question that was missing. Every door
 * into typing mode goes through it.
 */
internal fun startsSearchEditing(nowMs: Long, suppressSelectUntilMs: Long): Boolean =
    nowMs >= suppressSelectUntilMs

/**
 * How long after entering the screen a select press is taken for the one that opened it.
 *
 * Kept at the value the entry guard was written with: long enough for a press that is handed
 * on across the screen change, short enough that a user who deliberately presses select right
 * away does not lose it.
 */
internal const val SEARCH_SELECT_SUPPRESS_MS = 150L
