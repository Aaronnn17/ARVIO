// "View on Simkl" / "View on Trakt" from a details page: open the title's own
// page, not a search.
import { config } from "./config";
import type { MediaItem } from "./types";

type Ids = Pick<MediaItem, "id" | "imdbId" | "mediaType">;

/** Simkl's public redirect turns an IMDb/TMDB id into the title page (301). */
export function simklRedirectUrl(item: Ids): string {
  const params = new URLSearchParams({ to: "Simkl", type: item.mediaType === "movie" ? "movie" : "show" });
  if (item.imdbId) params.set("imdb", item.imdbId);
  else params.set("tmdb", String(item.id));
  if (config.simklClientId) params.set("client_id", config.simklClientId);
  return `https://api.simkl.com/redirect?${params.toString()}`;
}

export function traktSearchUrl(title: string): string {
  return `https://trakt.tv/search?query=${encodeURIComponent(title)}`;
}

const traktPages = new Map<string, Promise<string | null>>();

/** The title's Trakt page (trakt.tv/shows/<slug>), looked up by id once. */
export function traktTitleUrl(item: Ids): Promise<string | null> {
  if (!config.traktClientId) return Promise.resolve(null);
  const kind = item.mediaType === "movie" ? "movie" : "show";
  const [source, id] = item.imdbId ? ["imdb", item.imdbId] : ["tmdb", String(item.id)];
  const key = `${kind}:${source}:${id}`;
  const known = traktPages.get(key);
  if (known) return known;
  const lookup = (async () => {
    try {
      const response = await fetch(`https://api.trakt.tv/search/${source}/${encodeURIComponent(id)}?type=${kind}`, {
        headers: { "trakt-api-version": "2", "trakt-api-key": config.traktClientId },
        signal: typeof AbortSignal.timeout === "function" ? AbortSignal.timeout(8000) : undefined
      });
      if (!response.ok) return null;
      const results = await response.json() as Array<{ type?: string; movie?: { ids?: { slug?: string } }; show?: { ids?: { slug?: string } } }>;
      const slug = results.find((result) => result.type === kind)?.[kind]?.ids?.slug;
      return slug ? `https://trakt.tv/${kind === "movie" ? "movies" : "shows"}/${encodeURIComponent(slug)}` : null;
    } catch {
      return null;
    }
  })();
  traktPages.set(key, lookup);
  void lookup.then((url) => { if (!url) traktPages.delete(key); });
  return lookup;
}
