import type { MediaItem } from "./types";

/** Tracker list membership must not discard saved IPTV VOD sessions. */
export function includeIptvContinueWatching(primary: MediaItem[], local: MediaItem[]): MediaItem[] {
  const key = (item: MediaItem) => `${item.mediaType}:${item.id}`;
  const primaryKeys = new Set(primary.map(key));
  const newest = new Map<string, MediaItem>();
  for (const item of local) {
    const previous = newest.get(key(item));
    if (!previous || (item.activityAt ?? 0) > (previous.activityAt ?? 0)) newest.set(key(item), item);
  }
  const additions = [...newest.values()].filter((item) => {
    const progress = item.progress ?? 0;
    const position = item.resumePositionSeconds ?? 0;
    const duration = item.durationSeconds ?? 0;
    return !primaryKeys.has(key(item)) && item.id > 0 &&
      item.streamAddonId?.trim().toLowerCase() === "iptv_xtream_vod" &&
      !/^(live:|\[live\])/i.test(item.title) && !item.isWatched &&
      progress < 90 && (duration <= 0 || position / duration < 0.9) &&
      (progress >= 3 || position >= 60);
  });
  return [...primary, ...additions].sort((a, b) => (b.activityAt ?? 0) - (a.activityAt ?? 0));
}
