package com.arflix.tv.ui.screens.tv.live

import org.junit.Assert.assertEquals
import org.junit.Test

class HudControlBarTest {
    @Test fun controlsStayExactlyCentredWhenThereIsRoom() {
        // 1000 wide, 300-wide controls: centred at 350, clear of a 100 start and a 200 end.
        assertEquals(350, hudCenterGroupX(width = 1000, startWidth = 100, centerWidth = 300, endWidth = 200, gap = 20))
    }

    @Test fun wideActionsPushTheControlsAwayInsteadOfOverlapping() {
        // A 450-wide action group would reach the centred controls; they move to end before it.
        val x = hudCenterGroupX(width = 1000, startWidth = 100, centerWidth = 300, endWidth = 450, gap = 20)
        assertEquals(230, x)
        assertEquals(true, x + 300 + 20 <= 1000 - 450)
    }

    @Test fun aWideStartPushesTheControlsTheOtherWay() {
        assertEquals(470, hudCenterGroupX(width = 1000, startWidth = 450, centerWidth = 300, endWidth = 100, gap = 20))
    }

    @Test fun whenNothingFitsTheControlsKeepClearOfTheStart() {
        assertEquals(120, hudCenterGroupX(width = 1000, startWidth = 100, centerWidth = 600, endWidth = 400, gap = 20))
    }
}
