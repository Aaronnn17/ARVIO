import type { Category, MediaItem } from "./types";

export const HOME_WATCHLIST_ROW_ID = "home_watchlist";

/**
 * Android withHomeWatchlistRow (HomeWatchlist.kt): with the synced
 * "Watchlist on Home" setting on (default off) and a non-empty watchlist, a
 * Watchlist row follows Continue Watching, or leads Home when there is none.
 * A presentation row, never a saved catalog.
 */
export function withHomeWatchlistRow(categories: Category[], watchlist: MediaItem[], enabled: boolean): Category[] {
  const base = categories.filter((category) => category.id !== HOME_WATCHLIST_ROW_ID);
  const seen = new Set<string>();
  const items = watchlist.filter((item) => {
    const key = `${item.mediaType}:${item.id}`;
    if (!item.title?.trim() || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  if (!enabled || !items.length) return base;
  const insertion = base.findIndex((category) => category.id === "continue_watching") + 1;
  const next = [...base];
  next.splice(Math.max(0, insertion), 0, { id: HOME_WATCHLIST_ROW_ID, title: "Watchlist", items });
  return next;
}
