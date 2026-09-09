package com.arflix.tv.ui.screens.tv.live

import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvNowNext
import com.arflix.tv.data.model.IptvProgram
import com.arflix.tv.data.model.SportsEventArtwork
import com.arflix.tv.data.model.sportsArtworkKey
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/** Schedule facts, not stream probes. Channel identities remain provider-specific. */
internal data class SportsGuideEvent(
    val id: String,
    val title: String,
    val sport: GuideSport,
    val programme: IptvProgram,
    val channels: List<IptvChannel>,
    val artwork: String? = null,
) {
    fun isOnAir(now: Long) = programme.isLive(now)
}

internal fun attachSportsArtwork(events: List<SportsGuideEvent>, artwork: List<SportsEventArtwork>): List<SportsGuideEvent> {
    val byTitle = artwork.groupBy { it.key }
    return events.map { event ->
        val candidates = byTitle[sportsArtworkKey(event.title)].orEmpty().filter {
            val sport = GuideSport.fromText(it.genres.joinToString(" "))
            sport == null || sport == event.sport
        }
        event.copy(artwork = candidates.firstOrNull()?.background)
    }
}

internal enum class GuideSport(val title: String, val asset: String, val terms: Regex) {
    FOOTBALL("Football", "football", Regex("\\b(football|soccer|premier league|champions league|la liga|eredivisie|bundesliga)\\b")),
    BASKETBALL("Basketball", "basketball", Regex("\\b(basketball|nba|wnba|euroleague)\\b")),
    F1("Formula 1", "motor_sports", Regex("\\b(f1|formula 1|formula one)\\b")),
    TENNIS("Tennis", "tennis", Regex("\\b(tennis|atp|wta|wimbledon)\\b")),
    MMA("MMA", "fight", Regex("\\b(mma|ufc|bellator|pfl)\\b")),
    BOXING("Boxing", "fight", Regex("\\b(boxing|boxen)\\b")),
    AMERICAN_FOOTBALL("American football", "american_football", Regex("\\b(american football|nfl|ncaa football)\\b")),
    CRICKET("Cricket", "cricket", Regex("\\b(cricket|t20|ipl)\\b")),
    BASEBALL("Baseball", "baseball", Regex("\\b(baseball|mlb)\\b")),
    HOCKEY("Ice hockey", "hockey", Regex("\\b(ice hockey|hockey|nhl)\\b"));

    companion object {
        fun fromText(text: String): GuideSport? {
            val value = text.lowercase(Locale.ROOT)
            // Specific football codes must win over the generic word football.
            return listOf(AMERICAN_FOOTBALL, BASKETBALL, F1, TENNIS, MMA, BOXING,
                CRICKET, BASEBALL, HOCKEY, FOOTBALL).firstOrNull { it.terms.containsMatchIn(value) }
        }
    }
}

private val nonEvent = Regex("\\b(highlights?|replay|re-?run|classic|news|magazine|review|preview)\\b", RegexOption.IGNORE_CASE)
private val space = Regex("\\s+")

internal fun sportsProgrammeKey(programme: IptvProgram): String =
    "${programme.title.trim().lowercase(Locale.ROOT).replace(space, " ")}|${programme.startUtcMillis}|${programme.endUtcMillis}"

internal fun buildSportsGuideEvents(
    channels: List<IptvChannel>,
    guide: Map<String, IptvNowNext>,
    now: Long,
    zone: ZoneId = ZoneId.systemDefault(),
): List<SportsGuideEvent> {
    val end = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(2)
        .atStartOfDay(zone).toInstant().toEpochMilli()
    val events = linkedMapOf<String, SportsGuideEvent>()
    for (channel in channels) {
        val slice = guide[channel.id] ?: continue
        val programmes = (listOfNotNull(slice.now, slice.next, slice.later) + slice.upcoming)
            .distinctBy(::sportsProgrammeKey)
        for (programme in programmes) {
            if (programme.endUtcMillis <= now || programme.startUtcMillis >= end ||
                programme.endUtcMillis <= programme.startUtcMillis || programme.title.isBlank() ||
                nonEvent.containsMatchIn(programme.title)) continue
            val sport = GuideSport.fromText("${programme.title} ${programme.description.orEmpty()}")
                ?: GuideSport.fromText("${channel.group} ${channel.name}") ?: continue
            val id = "${sport.name}|${sportsProgrammeKey(programme)}"
            val previous = events[id]
            events[id] = if (previous == null) SportsGuideEvent(id, programme.title, sport, programme, listOf(channel))
            else if (previous.channels.none { it.id == channel.id }) previous.copy(channels = previous.channels + channel)
            else previous
        }
    }
    return events.values.sortedWith(compareByDescending<SportsGuideEvent> { it.isOnAir(now) }
        .thenBy { it.programme.startUtcMillis }.thenBy { it.title })
}

internal data class SportsGuideRow(val id: String, val title: String, val events: List<SportsGuideEvent>)

internal fun sportsGuideRows(events: List<SportsGuideEvent>, now: Long): List<SportsGuideRow> {
    val live = events.filter { it.isOnAir(now) }
    return buildList {
        // EPG has no viewer metrics. Never call this popularity or confirmed live sport.
        if (live.isNotEmpty()) add(SportsGuideRow("featured", "On air now", live.take(8)))
        val upcoming = events.filter { it.programme.startUtcMillis > now }
        if (upcoming.isNotEmpty()) add(SportsGuideRow("upcoming", "Upcoming today & tomorrow", upcoming))
        if (live.size > 8) add(SportsGuideRow("more", "More on air", live.drop(8)))
        GuideSport.entries.forEach { sport ->
            val items = live.filter { it.sport == sport }
            if (items.isNotEmpty()) add(SportsGuideRow(sport.name, sport.title, items))
        }
    }
}
