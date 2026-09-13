package com.arflix.tv.util

import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import org.junit.Test

class EpisodeAvailabilityTest {
    private val today = LocalDate.of(2026, 9, 13)

    @Test
    fun airedEpisodeIncludesToday() {
        assertThat(EpisodeAvailability.hasAired("2026-09-13", today)).isTrue()
    }

    @Test
    fun futureEpisodeIsNotAired() {
        assertThat(EpisodeAvailability.hasAired("2026-09-14", today)).isFalse()
    }

    @Test
    fun missingDateFailsClosedForWatchActions() {
        assertThat(EpisodeAvailability.hasAired("", today)).isFalse()
    }
}
