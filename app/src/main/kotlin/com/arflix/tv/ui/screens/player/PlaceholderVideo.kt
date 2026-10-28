package com.arflix.tv.ui.screens.player

/**
 * Addons answer a source they can't serve yet with a short stand-in video instead of an error:
 * AIOStreams' "downloading" / "error" clips are two minutes long, ElfHosted shows a "not cached yet"
 * slate. ExoPlayer plays them as normal files. A video of a few minutes where the source promised
 * hundreds of megabytes is such a stand-in, not the film or episode.
 */
private const val PLACEHOLDER_MAX_DURATION_MS = 5 * 60_000L
private const val PLACEHOLDER_MIN_PROMISED_BYTES = 300L * 1024 * 1024

internal fun isLikelyPlaceholderVideo(durationMs: Long, promisedSizeBytes: Long): Boolean =
    durationMs in 1..PLACEHOLDER_MAX_DURATION_MS && promisedSizeBytes >= PLACEHOLDER_MIN_PROMISED_BYTES
