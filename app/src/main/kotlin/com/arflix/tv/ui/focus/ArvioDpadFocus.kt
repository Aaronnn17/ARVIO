package com.arflix.tv.ui.focus

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.relocation.BringIntoViewResponder
import androidx.compose.foundation.relocation.bringIntoViewResponder
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.key.Key
import kotlin.Unit

@OptIn(ExperimentalFoundationApi::class, ExperimentalComposeUiApi::class)
fun Modifier.arvioDpadFocusGroup(
    restoreFocusRequester: FocusRequester? = null,
    enableFocusRestorer: Boolean = true
): Modifier {
    // Compose's focusRestorer(onRestoreFailed = { restoreFocusRequester }) captures the
    // requester at modifier-application time and, on a focus enter whose automatic restore
    // fails, calls requestFocus() ITSELF — deep inside the modifier, without a try/catch.
    // When the restore target lives in a LazyColumn row that is not yet composed/attached
    // (the case right after categories finish loading on a fresh TV entry), that internal
    // requestFocus() throws IllegalStateException: FocusRequester is not initialized and
    // crashes the app, unreachable by the runCatching guards wrapping direct calls.
    //
    // To keep the "land on the previously focused row on re-entry" behaviour without the
    // unguarded internal requestFocus, we enable the safe, default focusRestorer() (which
    // only saves/restores Compose's own focus history and never calls a caller-supplied
    // requester) and, when a restore target is requested, drive its focus ourselves on
    // focus enter via onFocusChanged with a runCatching guard.
    val restorer = if (enableFocusRestorer) Modifier.focusRestorer() else Modifier
    val restoreGuard = if (restoreFocusRequester != null) {
        Modifier.onFocusChanged { state ->
            if (state.hasFocus) {
                runCatching { restoreFocusRequester.requestFocus() }
            }
        }
    } else {
        Modifier
    }
    return this.then(restorer).then(restoreGuard).focusGroup()
}

@OptIn(ExperimentalFoundationApi::class)
private object ArvioNoOpBringIntoViewResponder : BringIntoViewResponder {
    override fun calculateRectForParent(localRect: Rect): Rect = localRect

    override suspend fun bringChildIntoView(localRect: () -> Rect?) = Unit
}

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.arvioManualBringIntoViewBoundary(): Modifier {
    return bringIntoViewResponder(ArvioNoOpBringIntoViewResponder)
}

fun isArvioDpadNavigationKey(key: Key): Boolean {
    return key == Key.DirectionLeft ||
        key == Key.DirectionRight ||
        key == Key.DirectionUp ||
        key == Key.DirectionDown
}

@Stable
class ArvioDpadRepeatGate(
    private val horizontalMinRepeatIntervalMs: Long,
    private val verticalMinRepeatIntervalMs: Long = horizontalMinRepeatIntervalMs
) {
    private var lastKeyCode: Int = Int.MIN_VALUE
    private var lastHandledAtMs: Long = 0L

    fun shouldSkip(keyCode: Int, repeatCount: Int, nowMs: Long): Boolean {
        if (repeatCount <= 0) {
            lastKeyCode = keyCode
            lastHandledAtMs = nowMs
            return false
        }

        val minRepeatIntervalMs = when (keyCode) {
            AndroidKeyEvent.KEYCODE_DPAD_UP,
            AndroidKeyEvent.KEYCODE_DPAD_DOWN -> verticalMinRepeatIntervalMs
            else -> horizontalMinRepeatIntervalMs
        }
        val skip = keyCode == lastKeyCode && nowMs - lastHandledAtMs < minRepeatIntervalMs
        if (!skip) {
            lastKeyCode = keyCode
            lastHandledAtMs = nowMs
        }
        return skip
    }

    fun reset() {
        lastKeyCode = Int.MIN_VALUE
        lastHandledAtMs = 0L
    }
}

@Composable
fun rememberArvioDpadRepeatGate(
    minRepeatIntervalMs: Long = 82L,
    horizontalMinRepeatIntervalMs: Long = minRepeatIntervalMs,
    verticalMinRepeatIntervalMs: Long = minRepeatIntervalMs
): ArvioDpadRepeatGate {
    return remember(horizontalMinRepeatIntervalMs, verticalMinRepeatIntervalMs) {
        ArvioDpadRepeatGate(
            horizontalMinRepeatIntervalMs = horizontalMinRepeatIntervalMs,
            verticalMinRepeatIntervalMs = verticalMinRepeatIntervalMs
        )
    }
}
