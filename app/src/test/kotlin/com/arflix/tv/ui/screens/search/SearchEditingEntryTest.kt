package com.arflix.tv.ui.screens.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Device report 15.09.2026, seen twice and reproduced by the user: opening the search screen on
 * a TV left the ring in the search bar with no keyboard on screen, every direction key dead and
 * only BACK getting out. The screen had come up in typing mode, switched on by the very press
 * that opened it and handed on to the new screen.
 *
 * The guard against it was half built — the window was opened on entry and never asked about.
 * These tests ask it: the doors into typing mode are modelled here exactly as `SearchScreen`
 * uses them, so what is checked is the real decision, not a copy of it.
 */
class SearchEditingEntryTest {
    private val entryMs = 10_000L
    private val windowEndsMs = entryMs + SEARCH_SELECT_SUPPRESS_MS

    /** The screen's three doors into typing mode, with the state they set. */
    private class TypingMode(private val suppressUntilMs: Long) {
        var editing = false
            private set
        var focusRequests = 0
            private set

        fun select(nowMs: Long) {
            if (!startsSearchEditing(nowMs, suppressUntilMs)) return
            editing = true
            focusRequests++
        }
    }

    private fun screenEntered() = TypingMode(windowEndsMs)

    @Test fun aSelectHandedOnFromTheOpeningPressDoesNotStartTyping() {
        val screen = screenEntered()
        screen.select(entryMs + 1)
        assertFalse("the press that opened the screen must not open the keyboard", screen.editing)
        assertEquals(0, screen.focusRequests)
    }

    @Test fun theScreenIsNotInTypingModeRightAfterItIsEntered() {
        // What this stands for on screen: with typing mode off, the screen's own D-pad handler
        // owns the direction keys again — down reaches the filter row instead of a keyboard
        // that is not there.
        val screen = screenEntered()
        screen.select(entryMs)
        assertFalse(screen.editing)
    }

    @Test fun aSelectAfterTheWindowStartsTypingAsBefore() {
        val screen = screenEntered()
        screen.select(windowEndsMs)
        assertTrue("the user's own press must still open the keyboard", screen.editing)
        assertEquals(1, screen.focusRequests)
    }

    @Test fun aSecondSelectStillAsksForTheKeyboardAgain() {
        // The nonce exists so a second select re-requests focus and keyboard even though
        // `editing` is already true — that must survive the guard.
        val screen = screenEntered()
        screen.select(windowEndsMs + 500)
        screen.select(windowEndsMs + 900)
        assertEquals(2, screen.focusRequests)
    }

    @Test fun theWindowIsShortEnoughToBeUnnoticeable() {
        assertTrue("a guard longer than a fifth of a second swallows deliberate presses",
            SEARCH_SELECT_SUPPRESS_MS <= 200L)
    }

    @Test fun theLastMillisecondOfTheWindowIsStillSuppressed() {
        assertFalse(startsSearchEditing(windowEndsMs - 1, windowEndsMs))
        assertTrue(startsSearchEditing(windowEndsMs, windowEndsMs))
    }
}
