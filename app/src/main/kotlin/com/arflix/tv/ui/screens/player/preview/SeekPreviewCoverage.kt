package com.arflix.tv.ui.screens.player.preview

internal const val PREVIEW_APPROXIMATION_MS = 20_000L
internal const val PREVIEW_SPECULATIVE_BYTES = 128L * 1024 * 1024

/** One bounded job at a time: local detail, five-minute coverage, then sparse title coverage. */
internal class SeekPreviewCoverage {
    private var turn = 0
    private var attempts = 0
    private val retryAfter = mutableMapOf<Long, Long>()

    fun next(positionMs: Long, durationMs: Long, sizeBytes: Long?, nowMs: Long,
        networkBytes: Long, cached: (Long) -> Boolean): Long? {
        if (durationMs <= 0) return null
        val wideBudgetAvailable = networkBytes < PREVIEW_SPECULATIVE_BYTES && attempts < 512
        val anchor = positionMs.coerceIn(0, durationMs - 1) / 10_000 * 10_000
        val local = seekPreviewWarmTargets(positionMs, durationMs)
        val ahead = sequence {
            // Cover jumps first, then fill the half-minute gaps.
            for (step in 1..5) yield(anchor + step * 60_000L)
            for (step in 0..9) yield(anchor + 30_000L + step * 30_000L)
        }
        val whole = sequence {
            // Unknown sizes and large remuxes keep speculative reads near playback.
            if (sizeBytes != null && sizeBytes in 1 until 20L * 1024 * 1024 * 1024) {
                // First pass every two minutes, then one minute, then thirty seconds.
                for (stride in listOf(120_000L, 60_000L, 30_000L)) {
                    var target = stride
                    while (target < durationMs) { yield(target); target += stride }
                }
            } else {
                for (step in 6..10) yield(anchor + step * 60_000L)
            }
        }
        // Local work cannot starve distant coverage as the playback clock advances.
        val phase = turn++ % 4
        val ordered = if (!wideBudgetAvailable) local.asSequence() else when (phase) {
            1 -> ahead + local.asSequence() + whole
            3 -> whole + ahead + local.asSequence()
            else -> local.asSequence() + ahead + whole
        }
        val target = ordered.filter { it in 0 until durationMs }
            .firstOrNull { (retryAfter[it] ?: 0) <= nowMs && !cached(it) } ?: return null
        if (kotlin.math.abs(target - positionMs) > 40_000L) attempts++
        // A failed sparse point must not trap every subsequent pass.
        retryAfter[target] = nowMs + 60_000L
        return target
    }
}
