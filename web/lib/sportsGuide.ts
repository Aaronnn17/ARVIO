import type { IptvChannel, IptvNowNext, IptvProgram } from "./types";

export const guideSports = [
  { id: "american-football", title: "American football", asset: "american_football", pattern: /\b(american football|nfl|ncaa football)\b/i },
  { id: "basketball", title: "Basketball", asset: "basketball", pattern: /\b(basketball|nba|wnba|euroleague)\b/i },
  { id: "f1", title: "Formula 1", asset: "motor_sports", pattern: /\b(f1|formula 1|formula one)\b/i },
  { id: "tennis", title: "Tennis", asset: "tennis", pattern: /\b(tennis|atp|wta|wimbledon)\b/i },
  { id: "mma", title: "MMA", asset: "fight", pattern: /\b(mma|ufc|bellator|pfl)\b/i },
  { id: "boxing", title: "Boxing", asset: "fight", pattern: /\b(boxing|boxen)\b/i },
  { id: "cricket", title: "Cricket", asset: "cricket", pattern: /\b(cricket|t20|ipl)\b/i },
  { id: "baseball", title: "Baseball", asset: "baseball", pattern: /\b(baseball|mlb)\b/i },
  { id: "hockey", title: "Ice hockey", asset: "hockey", pattern: /\b(ice hockey|hockey|nhl)\b/i },
  { id: "football", title: "Football", asset: "football", pattern: /\b(football|soccer|premier league|champions league|la liga|eredivisie|bundesliga)\b/i },
] as const;
export type GuideSport = typeof guideSports[number];
export interface SportsGuideEvent {
  id: string;
  title: string;
  sportId: GuideSport["id"];
  programme: IptvProgram;
  channels: IptvChannel[];
  artwork?: string;
}
const nonEvent = /\b(highlights?|replay|re-?run|classic|news|magazine|review|preview)\b/i;
export const sportsProgrammeKey = (p: IptvProgram) => `${p.title.trim().toLowerCase().replace(/\s+/g, " ")}|${p.startUtcMillis}|${p.endUtcMillis}`;
export const isOnAir = (event: SportsGuideEvent, now: number) => event.programme.startUtcMillis <= now && now < event.programme.endUtcMillis;

/** Inputs must already exclude hidden/locked groups. This never requests a stream. */
export function buildSportsGuideEvents(channels: IptvChannel[], guide: Record<string, IptvNowNext>, now: number, end?: number): SportsGuideEvent[] {
  const tomorrowEnd = new Date(now);
  tomorrowEnd.setDate(tomorrowEnd.getDate() + 2);
  tomorrowEnd.setHours(0, 0, 0, 0);
  const until = end ?? tomorrowEnd.getTime();
  const events = new Map<string, SportsGuideEvent>();
  for (const channel of channels) {
    const slice = guide[channel.id];
    if (!slice) continue;
    const programmes = [slice.now, slice.next, slice.later, ...slice.upcoming].filter((p): p is IptvProgram => Boolean(p));
    for (const programme of programmes) {
      if (!Number.isFinite(programme.startUtcMillis) || !Number.isFinite(programme.endUtcMillis) ||
          programme.endUtcMillis <= now || programme.startUtcMillis >= until || programme.endUtcMillis <= programme.startUtcMillis ||
          !programme.title.trim() || nonEvent.test(programme.title)) continue;
      const sport = guideSports.find((s) => s.pattern.test(`${programme.title} ${programme.description ?? ""}`))
        ?? guideSports.find((s) => s.pattern.test(`${channel.group} ${channel.name}`));
      if (!sport) continue;
      const id = `${sport.id}|${sportsProgrammeKey(programme)}`;
      const old = events.get(id);
      if (!old) events.set(id, { id, title: programme.title, sportId: sport.id, programme, channels: [channel] });
      else if (!old.channels.some((ch) => ch.id === channel.id)) old.channels.push(channel);
    }
  }
  return [...events.values()].sort((a, b) => Number(isOnAir(b, now)) - Number(isOnAir(a, now)) || a.programme.startUtcMillis - b.programme.startUtcMillis || a.title.localeCompare(b.title));
}

export function sportsGuideRows(events: SportsGuideEvent[], now: number) {
  const live = events.filter((event) => isOnAir(event, now));
  return [
    { id: "featured", title: "On air now", events: live.slice(0, 8) },
    { id: "upcoming", title: "Upcoming today & tomorrow", events: events.filter((event) => event.programme.startUtcMillis > now) },
    { id: "more", title: "More on air", events: live.slice(8) },
    ...["football", "basketball", "f1", "tennis", "mma", "boxing", "american-football", "cricket", "baseball", "hockey"]
      .map((id) => guideSports.find((sport) => sport.id === id)!)
      .map((sport) => ({ id: sport.id, title: sport.title, events: live.filter((event) => event.sportId === sport.id) })),
  ].filter((row) => row.events.length > 0);
}
