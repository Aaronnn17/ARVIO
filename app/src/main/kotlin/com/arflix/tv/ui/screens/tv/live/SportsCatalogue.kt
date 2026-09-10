package com.arflix.tv.ui.screens.tv.live

import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvProgram
import com.arflix.tv.data.model.SportsEventArtwork
import com.arflix.tv.data.model.sportsEventIdentity
import com.arflix.tv.data.model.sportsArtworkKey
import com.arflix.tv.data.model.sportsQualifierKey
import java.time.Instant
import java.time.ZoneId

/** Editorial priority plus broadcast reach, never a claim of measured viewers. */
internal fun sportsProminence(league: String?, countries: Int = 0): Int {
    val name = league.orEmpty().lowercase(java.util.Locale.ROOT)
    val major = setOf("uefa champions league", "english premier league", "premier league", "spanish la liga", "la liga", "nba", "nfl", "formula 1", "ufc", "fifa world cup")
    val featured = setOf("italian serie a", "serie a", "german bundesliga", "bundesliga", "french ligue 1", "ligue 1", "nhl", "mlb", "wimbledon", "us open", "atp us open", "wta us open", "indian premier league")
    return (if (name in major) 200 else if (name in featured) 100 else 0) + countries.coerceIn(0, 50) * 2
}

private val channelQuality = Regex("\\b(uhd|fhd|hd|sd|4k|8k|hevc|h265|h264)\\b", RegexOption.IGNORE_CASE)
internal fun sportsChannelKey(name: String) = sportsArtworkKey(name.replace(channelQuality, ""))
    .replace(Regex("^(uk|gb|us|usa|nl|de|fr|es|it|pt|br|au|ca)\\s+(?:nowtv|raw|backup)\\s+"), "$1 ")
    .replace(Regex("\\btnt sport\\b"), "tnt sports").replace(Regex("\\s+"), " ").trim()
internal fun sportsBroadcasterKeys(name: String, country: String): List<String> {
    val regions = mapOf("united kingdom" to listOf("uk", "gb"), "united states" to listOf("us", "usa"), "netherlands" to listOf("nl"),
        "germany" to listOf("de"), "france" to listOf("fr"), "spain" to listOf("es"), "italy" to listOf("it"), "portugal" to listOf("pt"),
        "brazil" to listOf("br"), "australia" to listOf("au"), "canada" to listOf("ca"))
    val codes = regions[country.lowercase(java.util.Locale.ROOT)].orEmpty()
    val key = sportsChannelKey(name)
    // TV listings often include the country in the name, e.g. ESPN 3 Netherlands.
    // Strip only the explicitly supplied country, never another region or channel number.
    val countrySuffix = " ${sportsArtworkKey(country)}"
    val localName = if (country.isNotBlank() && key.endsWith(countrySuffix)) key.removeSuffix(countrySuffix) else key
    return (listOf(key, localName) + codes.flatMap { listOf("$it $localName", "$localName $it") }).distinct()
}
private fun leagueKey(name: String): String {
    val key = sportsArtworkKey(name)
    return if (key in setOf("english premier league", "spanish la liga", "italian serie a", "german bundesliga", "french ligue 1")) key.substringAfter(' ') else key
}

internal fun buildSportsCatalogue(guide: List<SportsGuideEvent>, artwork: List<SportsEventArtwork>, channels: List<IptvChannel>, now: Long,
    zone: ZoneId = ZoneId.systemDefault()): List<SportsGuideEvent> {
    val fixtures = artwork.filter { it.fixture != null && it.startsAt != null }
    if (fixtures.isEmpty()) return attachSportsArtwork(guide, artwork)
    val byIdentity = guide.groupBy { "${it.sport}|${it.identity}" }
    val guideTitles = guide.associate { it.id to " ${sportsArtworkKey(it.title)} " }
    val byChannel = channels.groupBy { sportsChannelKey(it.name) }
    val used = hashSetOf<String>()
    val seen = hashSetOf<String>()
    val until = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(2).atStartOfDay(zone).toInstant().toEpochMilli()
    val output = fixtures.mapNotNull { item ->
        val fixture = item.fixture!!; val start = item.startsAt!!
        val sport = GuideSport.fromText(item.genres.joinToString(" ")) ?: return@mapNotNull null
        if (!seen.add(fixture.id) || start >= until || start < now - 86_400_000) return@mapNotNull null
        val home = item.homeTeam?.let(::sportsArtworkKey)
        val away = item.awayTeam?.let(::sportsArtworkKey)
        // Both complete participant names must be present; a league or one team is not enough.
        val candidates = if (home != null && away != null && home != away && home.length >= 4 && away.length >= 4)
            guide.filter { it.sport == sport && guideTitles.getValue(it.id).contains(" $home ") && guideTitles.getValue(it.id).contains(" $away ") }
            else emptyList()
        val matches = (byIdentity["$sport|${sportsEventIdentity(item.title)}"].orEmpty() + candidates).distinctBy { it.id }.filter { event ->
            event.id !in used && kotlin.math.abs(event.programme.startUtcMillis - start) <= 2 * 3600_000L &&
                sportsQualifierKey("${event.title} ${event.competition.orEmpty()}") == sportsQualifierKey("${item.title} ${fixture.league.orEmpty()}") &&
                (fixture.qualifier == null || "${event.title} ${event.competition.orEmpty()}".contains(fixture.qualifier, true)) &&
                (event.competition == null || fixture.league == null || leagueKey(event.competition) == leagueKey(fixture.league))
        }
        matches.forEach { used.add(it.id) }
        val mapped = matches.flatMap { it.channels }.distinctBy { it.id }
        val mappedIds = mapped.mapTo(hashSetOf()) { it.id }
        val possible = fixture.broadcasters.filter { kotlin.math.abs(it.startsAt - start) < 2 * 3600_000L }
            .flatMap { b -> sportsBroadcasterKeys(b.name, b.country).flatMap { byChannel[it].orEmpty() } }.filter { it.id !in mappedIds }.distinctBy { it.id }
        // Finished metadata suppresses a stale EPG entry; it must not reappear as a fallback.
        if (fixture.status in setOf("finished", "postponed")) return@mapNotNull null
        SportsGuideEvent(id = "sportsdb:${fixture.id}", title = item.title, sport = sport,
            programme = IptvProgram(title = item.title, startUtcMillis = start, endUtcMillis = start),
            channels = mapped, schedules = matches.flatMap { it.schedules.entries }.associate { it.toPair() },
            artwork = item.background.takeIf { it.isNotBlank() } ?: matches.firstNotNullOfOrNull { it.artwork },
            teamArtwork = item.takeIf { it.homeBadge != null && it.awayBadge != null }, artworkSource = "TheSportsDB",
            competition = fixture.league, fixture = fixture, possibleChannels = possible,
            prominence = sportsProminence(fixture.league, fixture.broadcasters.map { it.country }.filter { it.isNotBlank() }.distinct().size))
    }
    return output + attachSportsArtwork(guide.filter { it.id !in used }, artwork)
}
