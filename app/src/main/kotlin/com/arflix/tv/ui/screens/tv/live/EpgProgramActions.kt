package com.arflix.tv.ui.screens.tv.live

internal enum class EpgTemporalState {
    Live,
    Past,
    Future,
}

internal enum class EpgInteractionAction {
    PlayLiveMini,
    PlayLiveFullscreen,
    PlayCatchup,
    NoOp,
}

internal fun channelRowInteractionAction(
    isSamePlayingChannel: Boolean,
): EpgInteractionAction = if (isSamePlayingChannel) {
    EpgInteractionAction.PlayLiveFullscreen
} else {
    EpgInteractionAction.PlayLiveMini
}

internal fun epgProgramInteractionAction(
    temporalState: EpgTemporalState,
    isSamePlayingChannel: Boolean,
    isCatchupSupported: Boolean,
): EpgInteractionAction = when (temporalState) {
    EpgTemporalState.Live -> channelRowInteractionAction(isSamePlayingChannel)
    EpgTemporalState.Past -> if (isCatchupSupported) {
        EpgInteractionAction.PlayCatchup
    } else {
        EpgInteractionAction.NoOp
    }
    EpgTemporalState.Future -> EpgInteractionAction.NoOp
}
