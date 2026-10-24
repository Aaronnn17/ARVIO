import { getDetails, getSeasonEpisodes } from "@/lib/tmdb";
import type { ProviderPriorityConfig } from "@/lib/metadata/types";
import type { EpisodeInfo, MediaItem } from "@/lib/types";

// One in-flight request per key. Opening a series used to fire tv/{id} three
// times in the same millisecond (store.openDetails, the details view mount and
// its re-run when the hydrated item replaced the shallow one) and every season
// and per-episode rating request twice; the cache in tmdb.ts only helps once a
// response has landed. Sharing the pending promise collapses those into one.

export function createInFlight<K, V>() {
  const pending = new Map<K, Promise<V>>();
  return (key: K, run: () => Promise<V>): Promise<V> => {
    const existing = pending.get(key);
    if (existing) return existing;
    const task = run().finally(() => { if (pending.get(key) === task) pending.delete(key); });
    pending.set(key, task);
    return task;
  };
}

const detailsInFlight = createInFlight<string, MediaItem>();
const seasonInFlight = createInFlight<string, EpisodeInfo[]>();

function configKey(config?: ProviderPriorityConfig) {
  return config ? JSON.stringify(config) : "";
}

export function loadDetails(item: MediaItem, config?: ProviderPriorityConfig) {
  return detailsInFlight(`${item.mediaType}:${item.id}:${configKey(config)}`, () => getDetails(item, config));
}

export function loadSeasonEpisodes(
  tvId: number,
  season: number,
  language = "en-US",
  config?: ProviderPriorityConfig,
  context?: Parameters<typeof getSeasonEpisodes>[4]
) {
  const key = `${tvId}:${season}:${language}:${configKey(config)}:${context?.tvdbId ?? ""}:${context?.anilistId ?? ""}:${context?.isAnime ? 1 : 0}`;
  return seasonInFlight(key, () => getSeasonEpisodes(tvId, season, language, config, context));
}
