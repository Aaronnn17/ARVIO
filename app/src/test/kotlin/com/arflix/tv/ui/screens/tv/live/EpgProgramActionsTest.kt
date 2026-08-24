package com.arflix.tv.ui.screens.tv.live

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class EpgProgramActionsTest {

    @Test
    fun channelRowFirstClickTunesLiveMiniPlayer() {
        assertThat(channelRowInteractionAction(isSamePlayingChannel = false))
            .isEqualTo(EpgInteractionAction.PlayLiveMini)
    }

    @Test
    fun channelRowSecondClickOpensLiveFullscreen() {
        assertThat(channelRowInteractionAction(isSamePlayingChannel = true))
            .isEqualTo(EpgInteractionAction.PlayLiveFullscreen)
    }

    @Test
    fun liveEpgCellFirstClickTunesLiveMiniPlayer() {
        assertThat(
            epgProgramInteractionAction(
                temporalState = EpgTemporalState.Live,
                isSamePlayingChannel = false,
                isCatchupSupported = false,
            )
        ).isEqualTo(EpgInteractionAction.PlayLiveMini)
    }

    @Test
    fun liveEpgCellSecondClickOpensLiveFullscreen() {
        assertThat(
            epgProgramInteractionAction(
                temporalState = EpgTemporalState.Live,
                isSamePlayingChannel = true,
                isCatchupSupported = false,
            )
        ).isEqualTo(EpgInteractionAction.PlayLiveFullscreen)
    }

    @Test
    fun pastEpgCellWithCatchupStartsCatchup() {
        assertThat(
            epgProgramInteractionAction(
                temporalState = EpgTemporalState.Past,
                isSamePlayingChannel = false,
                isCatchupSupported = true,
            )
        ).isEqualTo(EpgInteractionAction.PlayCatchup)
    }

    @Test
    fun pastEpgCellWithoutCatchupDoesNothing() {
        assertThat(
            epgProgramInteractionAction(
                temporalState = EpgTemporalState.Past,
                isSamePlayingChannel = false,
                isCatchupSupported = false,
            )
        ).isEqualTo(EpgInteractionAction.NoOp)
    }

    @Test
    fun futureEpgCellDoesNothing() {
        assertThat(
            epgProgramInteractionAction(
                temporalState = EpgTemporalState.Future,
                isSamePlayingChannel = false,
                isCatchupSupported = false,
            )
        ).isEqualTo(EpgInteractionAction.NoOp)
    }
}
