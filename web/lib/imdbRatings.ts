import { config } from "./config";
import { loadStored, saveStored } from "./storage";

// Real IMDb ratings — parity with the Android app (MediaRepository.getImdbRating).
// TMDB's vote_average is a DIFFERENT score and was previously rendered under an
// IMDb badge, so every number looked wrong next to IMDb. Cinemeta carries the
// actual IMDb rating and is keyed by imdb id, exactly like the app uses it.
//
// Cost: Cinemeta is on the resolver worker's proxy allowlist AND its cacheable
// set, so lookups are served from Cloudflare's edge cache — no Netlify function
// invocations. On top of that we keep a per-session memory cache and a
// localStorage cache, so a rating is fetched at most once per title per week.

type CacheEntry = { rating: string; at: number };

const MEMORY = new Map<string, string>();
const INFLIGHT = new Map<string, Promise<string | null>>();
const STORE_KEY = "arvio.web.imdbRatings.v1";
const TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_ENTRIES = 600;

function readStore(): Record<string, CacheEntry> {
  return loadStored<Record<string, CacheEntry>>(STORE_KEY, {});
}

function writeStore(store: Record<string, CacheEntry>) {
  // Bound the cache so it can never grow into the localStorage quota (a full
  // quota silently kills every other write in the app).
  const entries = Object.entries(store);
  if (entries.length > MAX_ENTRIES) {
    const keep = entries.sort((a, b) => b[1].at - a[1].at).slice(0, MAX_ENTRIES);
    store = Object.fromEntries(keep);
  }
  saveStored(STORE_KEY, store);
}

function cached(imdbId: string): string | null {
  const hit = MEMORY.get(imdbId);
  if (hit !== undefined) return hit;
  const entry = readStore()[imdbId];
  if (entry && Date.now() - entry.at < TTL_MS) {
    MEMORY.set(imdbId, entry.rating);
    return entry.rating;
  }
  return null;
}

function remember(imdbId: string, rating: string) {
  MEMORY.set(imdbId, rating);
  const store = readStore();
  store[imdbId] = { rating, at: Date.now() };
  writeStore(store);
}

function cinemetaUrl(mediaType: "movie" | "tv", imdbId: string) {
  const typePath = mediaType === "tv" ? "series" : "movie";
  const target = `https://v3-cinemeta.strem.io/meta/${typePath}/${imdbId}.json`;
  const base = config.resolverUrl.replace(/\/+$/, "");
  // Route through the resolver worker: it is CORS-clean and edge-caches
  // Cinemeta. Without a resolver configured, go direct (Cinemeta allows CORS).
  return base ? `${base}/proxy?url=${encodeURIComponent(target)}` : target;
}

function normalize(raw: unknown): string | null {
  const value = typeof raw === "number" ? raw : Number(String(raw ?? "").trim());
  if (!Number.isFinite(value) || value <= 0) return null;
  return value.toFixed(1);
}

/**
 * The IMDb rating for a title, or null when Cinemeta doesn't know it (common
 * for very new or obscure entries — the caller should then show no badge
 * rather than substituting a different provider's score).
 */
export async function getImdbRating(mediaType: "movie" | "tv", imdbId?: string | null): Promise<string | null> {
  const id = (imdbId ?? "").trim().toLowerCase();
  if (!/^tt\d+$/.test(id)) return null;
  const hit = cached(id);
  if (hit !== null) return hit || null;

  const existing = INFLIGHT.get(id);
  if (existing) return existing;

  const request = (async () => {
    try {
      const response = await fetch(cinemetaUrl(mediaType, id), {
        headers: { Accept: "application/json" },
        signal: typeof AbortSignal.timeout === "function" ? AbortSignal.timeout(8000) : undefined
      });
      if (!response.ok) return null;
      const payload = await response.json() as { meta?: { imdbRating?: unknown } };
      const rating = normalize(payload?.meta?.imdbRating);
      // Cache misses too (as an empty string) so a title Cinemeta has no rating
      // for isn't re-fetched on every render for the next week.
      remember(id, rating ?? "");
      return rating;
    } catch {
      return null;
    } finally {
      INFLIGHT.delete(id);
    }
  })();
  INFLIGHT.set(id, request);
  return request;
}
