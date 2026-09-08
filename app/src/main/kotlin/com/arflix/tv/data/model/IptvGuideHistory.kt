package com.arflix.tv.data.model

/** Provider archive bounds, shared by guide storage, refresh decisions and the fullscreen guide. */
internal object IptvGuideHistory {
    const val DAY_MS = 24L * 60L * 60_000L
    const val MAX_WINDOW_MS = 7L * DAY_MS
    const val MAX_PROGRAMS = 1_000

    fun days(channel: IptvChannel?, force: Boolean = false): Int {
        if (channel == null) return 0
        val explicit = channel.catchupDays.coerceIn(0, 7)
        if (explicit > 0) return explicit
        if (!channel.catchupType.isNullOrBlank() || !channel.catchupSource.isNullOrBlank() ||
            channel.streamUrl.contains("/timeshift/", ignoreCase = true)
        ) return 7
        if (force || channel.xtreamStreamId != null || channel.streamUrl.contains("/live/", ignoreCase = true)) return 3
        return 0
    }

    fun hasCoverage(item: IptvNowNext?, windowMs: Long, nowMs: Long): Boolean {
        if (windowMs <= 0L) return true
        val oldest = item?.recent.orEmpty().asSequence()
            .filter { it.endUtcMillis <= nowMs && it.endUtcMillis > nowMs - windowMs }
            .minOfOrNull { it.startUtcMillis } ?: return false
        // Count alone is misleading: 24 five-minute programmes cover only two hours.
        return nowMs - oldest >= windowMs - minOf(3 * 60 * 60_000L, windowMs / 4)
    }
}
