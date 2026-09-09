import { jsonRequest, proxiedUrl } from "./http";
import { guideSports, type SportsGuideEvent } from "./sportsGuide";
import type { InstalledAddon } from "./types";

export interface SportsEventArtwork { title: string; key: string; background: string; genres: string[] }
export const sportsArtworkKey = (title: string) => title.normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase()
  .replace(/^(live\s*[:|-]\s*|live\s+)/, "").replace(/^(football|soccer|basketball|baseball|tennis|ice hockey|american football|boxing|mma|cricket)\s*:\s*/, "")
  .replace(/\b(vs\.?|versus|v\.)\s+/g, "vs ")
  .replace(/[^\p{L}\p{N}]+/gu, " ").trim();

export function toSportsEventArtwork(meta: Record<string, unknown>): SportsEventArtwork | null {
  if (!meta || typeof meta !== "object") return null;
  if (typeof meta.name !== "string" || !meta.name.trim() || String(meta.id).startsWith("leaf:")) return null;
  // Event backgrounds are untimed; posters can have a foreign timezone baked into them.
  if (typeof meta.background !== "string" || /_UTC/i.test(meta.background)) return null;
  try { if (!["https:", "http:"].includes(new URL(meta.background).protocol)) return null; } catch { return null; }
  return { title: meta.name, key: sportsArtworkKey(meta.name), background: meta.background,
    genres: Array.isArray(meta.genres) ? meta.genres.filter((g): g is string => typeof g === "string") : [] };
}

export function attachSportsArtwork(events: SportsGuideEvent[], artwork: SportsEventArtwork[]): SportsGuideEvent[] {
  const byTitle = new Map<string, SportsEventArtwork[]>();
  for (const item of artwork) byTitle.set(item.key, [...(byTitle.get(item.key) ?? []), item]);
  return events.map(event => ({ ...event, artwork: byTitle.get(sportsArtworkKey(event.title))?.find(item => {
    const sport = guideSports.find(s => s.pattern.test(item.genres.join(" ")));
    return !sport || sport.id === event.sportId;
  })?.background }));
}

const cache = new Map<string, { until: number; request: Promise<SportsEventArtwork[]> }>();
const sportsCatalog = /sport|football|soccer|basketball|tennis|motorsport|formula|racing|rugby|hockey|baseball|boxing|ufc|mma|cricket|golf/i;
export function loadSportsGuideArtwork(addons: InstalledAddon[]): Promise<SportsEventArtwork[]> {
  const requests = addons.filter(addon => addon.enabled !== false && addon.resources.some(r => /^(stream|streams)$/i.test(typeof r === "string" ? r : r.name))
    && addon.catalogs.some(c => sportsCatalog.test(`${c.type} ${c.id} ${c.name}`))).slice(0, 2)
    .flatMap(addon => addon.catalogs.filter(c => sportsCatalog.test(`${c.type} ${c.id} ${c.name}`))
      .map(catalog => { const text = `${catalog.id} ${catalog.name}`.toLowerCase(); return { catalog, rank: text.includes("today") ? 0 : text.includes("live") ? 1 : text.includes("all") ? 2 : 3 }; })
      .sort((a, b) => a.rank - b.rank).slice(0, 3).map(({ catalog }) =>
        `${addon.manifestUrl.replace(/\/manifest\.json$/, "").replace(/\/+$/, "")}/catalog/${encodeURIComponent(catalog.type)}/${encodeURIComponent(catalog.id)}.json`));
  const key = JSON.stringify(requests);
  const stored = cache.get(key);
  if (stored && stored.until > Date.now()) return stored.request;
  const entry = { until: Date.now() + 10 * 60_000, request: Promise.resolve([] as SportsEventArtwork[]) };
  entry.request = Promise.all(requests.map(async url => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5_000);
    try {
      const payload = await jsonRequest<{ metas?: Record<string, unknown>[]; items?: Record<string, unknown>[] }>(proxiedUrl(url), { signal: controller.signal });
      const metas = payload.metas ?? payload.items;
      return Array.isArray(metas) ? metas.slice(0, 500).map(toSportsEventArtwork).filter((item): item is SportsEventArtwork => Boolean(item)) : [];
    } catch { return []; } finally { clearTimeout(timer); }
  })).then(results => {
    const items = [...new Map(results.flat().map(item => [`${item.key}|${item.background}`, item])).values()].slice(0, 1_000);
    if (!items.length) entry.until = Date.now() + 60_000;
    return items;
  });
  if (cache.size >= 4) cache.delete(cache.keys().next().value!);
  cache.set(key, entry);
  return entry.request;
}
