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

/**
 * The title's Trakt page. The relay looks it up by IMDb/TMDB id and redirects
 * (the browser build has no Trakt key and Trakt blocks the app backend);
 * without a relay, or when Trakt doesn't know the id, it opens a title search.
 */
export function traktLinkUrl(item: Ids & { title: string }, relayHasLink: boolean): string {
  const relay = (config.resolverUrl || "").replace(/\/+$/, "");
  if (!relayHasLink || !/^https?:/.test(relay)) return traktSearchUrl(item.title);
  const params = new URLSearchParams({ type: item.mediaType === "movie" ? "movie" : "show", title: item.title });
  if (item.imdbId) params.set("imdb", item.imdbId);
  else params.set("tmdb", String(item.id));
  return `${relay}/trakt/link?${params.toString()}`;
}

let traktLinkSupport: Promise<boolean> | null = null;
/** Whether the deployed relay has the /trakt/link redirect (its /health lists it). */
export function relaySupportsTraktLink(): Promise<boolean> {
  const relay = (config.resolverUrl || "").replace(/\/+$/, "");
  if (!/^https?:/.test(relay)) return Promise.resolve(false);
  traktLinkSupport ??= fetch(`${relay}/health`, { cache: "no-store" })
    .then((response) => response.ok ? response.json() as Promise<{ features?: string[] }> : null)
    .then((health) => Boolean(health?.features?.includes("trakt-link")))
    .catch(() => false);
  return traktLinkSupport;
}
