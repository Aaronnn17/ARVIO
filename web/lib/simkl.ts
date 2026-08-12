import { SyncClient, SyncMediaRef } from "./sync";
import { loadStored, removeStored, saveStored } from "./storage";
import { jsonRequest } from "./http";

const SIMKL_TOKEN_KEY = "arvio.web.simkl.token";

export interface SimklToken {
  access_token: string;
}

export interface SimklPinCode {
  user_code: string;
  verification_url: string;
  expires_in: number;
  interval: number;
}

function extractItems<T>(res: unknown, key: "movies" | "shows" | "anime"): T[] {
  if (!res) return [];
  if (Array.isArray(res)) return res as T[];
  if (typeof res === "object" && res !== null && key in res) {
    const list = (res as Record<string, unknown>)[key];
    if (Array.isArray(list)) return list as T[];
  }
  return [];
}

export class SimklClient implements SyncClient {
  token: SimklToken | null = loadStored<SimklToken | null>(SIMKL_TOKEN_KEY, null);

  get isConnected(): boolean {
    return Boolean(this.token?.access_token);
  }

  setToken(token: SimklToken | null) {
    this.token = token;
    if (this.token) saveStored(SIMKL_TOKEN_KEY, this.token);
    else removeStored(SIMKL_TOKEN_KEY);
  }

  disconnect() {
    this.setToken(null);
  }

  private async simkl<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      ...(options.headers as Record<string, string>)
    };
    if (this.token?.access_token) {
      headers["x-user-token"] = this.token.access_token;
    }
    return jsonRequest<T>(`/api/simkl${path}`, { ...options, headers });
  }

  async beginPinAuth(): Promise<SimklPinCode> {
    return this.simkl<SimklPinCode>("/oauth/pin");
  }

  async pollPinToken(userCode: string): Promise<boolean> {
    type PollRes = { result: string; access_token?: string; message?: string };
    const res = await this.simkl<PollRes>(`/oauth/pin/${userCode}`);
    if (res.result === "OK" && res.access_token) {
      this.setToken({ access_token: res.access_token });
      return true;
    }
    return false;
  }

  /**
   * Watchlist: fetch movies, shows, and anime concurrently, filter items with status "plantowatch",
   * and map them to standard trakt/simkl item structures for UI consumption.
   */
  async watchlist(): Promise<unknown[]> {
    if (!this.isConnected) return [];
    try {
      const [moviesRes, showsRes, animeRes] = await Promise.all([
        this.simkl<unknown>("/sync/all-items/movies").catch(() => null),
        this.simkl<unknown>("/sync/all-items/shows").catch(() => null),
        this.simkl<unknown>("/sync/all-items/anime").catch(() => null)
      ]);

      type SimklMovieRow = { movie?: { title?: string; year?: number; ids?: { tmdb?: number; simkl?: number; imdb?: string } }; status?: string; last_watched_at?: string };
      type SimklShowRow = { show?: { title?: string; year?: number; ids?: { tmdb?: number; simkl?: number; imdb?: string } }; status?: string; last_watched_at?: string };

      const movies = extractItems<SimklMovieRow>(moviesRes, "movies")
        .filter((item) => item.status === "plantowatch" && item.movie?.ids?.tmdb)
        .map((item) => ({
          type: "movie",
          movie: item.movie,
          listed_at: item.last_watched_at
        }));

      const shows = extractItems<SimklShowRow>(showsRes, "shows")
        .filter((item) => item.status === "plantowatch" && item.show?.ids?.tmdb)
        .map((item) => ({
          type: "show",
          show: item.show,
          listed_at: item.last_watched_at
        }));

      const anime = extractItems<SimklShowRow>(animeRes, "anime")
        .filter((item) => item.status === "plantowatch" && item.show?.ids?.tmdb)
        .map((item) => ({
          type: "show",
          show: item.show,
          listed_at: item.last_watched_at
        }));

      return [...movies, ...shows, ...anime];
    } catch {
      return [];
    }
  }

  async playback(): Promise<unknown[]> {
    return [];
  }

  /**
   * Watched items:
   * For movies -> /sync/all-items/movies (filtered by completed/watching/last_watched_at)
   * For shows -> combines /sync/all-items/shows and /sync/all-items/anime (with granular episode records)
   */
  async watched(type: "movies" | "shows"): Promise<unknown[]> {
    if (!this.isConnected) return [];
    try {
      if (type === "movies") {
        const res = await this.simkl<unknown>("/sync/all-items/movies").catch(() => null);
        type SimklMovieRow = { movie?: { title?: string; year?: number; ids?: { tmdb?: number; simkl?: number; imdb?: string } }; status?: string; last_watched_at?: string };
        return extractItems<SimklMovieRow>(res, "movies").filter(
          (item) => item.movie?.ids?.tmdb && (item.status === "completed" || item.status === "watching" || Boolean(item.last_watched_at))
        );
      } else {
        const [showsRes, animeRes] = await Promise.all([
          this.simkl<unknown>("/sync/all-items/shows").catch(() => null),
          this.simkl<unknown>("/sync/all-items/anime").catch(() => null)
        ]);
        type SimklShowRow = { show?: { title?: string; year?: number; ids?: { tmdb?: number; simkl?: number; imdb?: string } }; status?: string; last_watched_at?: string; seasons?: Array<{ number?: number; episodes?: Array<{ number?: number }> }> };
        const shows = extractItems<SimklShowRow>(showsRes, "shows");
        const anime = extractItems<SimklShowRow>(animeRes, "anime");
        return [...shows, ...anime];
      }
    } catch {
      return [];
    }
  }

  /**
   * Add movie, show, or anime to Watchlist ("plantowatch") via /sync/add-to-list.
   */
  async addToWatchlist(item: SyncMediaRef): Promise<void> {
    if (!this.isConnected) return;
    const body = item.mediaType === "movie"
      ? { movies: [{ to: "plantowatch", ids: { tmdb: item.tmdbId } }] }
      : { shows: [{ to: "plantowatch", ids: { tmdb: item.tmdbId } }] };
    await this.simkl("/sync/add-to-list", { method: "POST", body: JSON.stringify(body) });
  }

  /**
   * Remove item from watchlist. Uses /sync/history/remove for unwatched items.
   */
  async removeFromWatchlist(item: SyncMediaRef): Promise<void> {
    if (!this.isConnected) return;
    const body = item.mediaType === "movie"
      ? { movies: [{ ids: { tmdb: item.tmdbId } }] }
      : { shows: [{ ids: { tmdb: item.tmdbId } }] };
    await this.simkl("/sync/history/remove", { method: "POST", body: JSON.stringify(body) });
  }

  /**
   * Mark movie, entire show, or specific episode as watched via /sync/history?allow_rewatch=yes.
   */
  async addToHistory(item: SyncMediaRef): Promise<void> {
    if (!this.isConnected) return;
    const hasEpisode = typeof item.season === "number" && typeof item.episode === "number";
    const body = item.mediaType === "movie"
      ? { movies: [{ ids: { tmdb: item.tmdbId } }] }
      : {
          shows: [{
            ids: { tmdb: item.tmdbId },
            seasons: hasEpisode ? [{ number: item.season!, episodes: [{ number: item.episode! }] }] : undefined
          }]
        };
    await this.simkl("/sync/history?allow_rewatch=yes", { method: "POST", body: JSON.stringify(body) });
  }

  /**
   * Mark movie, entire show, or specific episode as unwatched via /sync/history/remove.
   */
  async removeFromHistory(item: SyncMediaRef): Promise<void> {
    if (!this.isConnected) return;
    const hasEpisode = typeof item.season === "number" && typeof item.episode === "number";
    const body = item.mediaType === "movie"
      ? { movies: [{ ids: { tmdb: item.tmdbId } }] }
      : {
          shows: [{
            ids: { tmdb: item.tmdbId },
            seasons: hasEpisode ? [{ number: item.season!, episodes: [{ number: item.episode! }] }] : undefined
          }]
        };
    await this.simkl("/sync/history/remove", { method: "POST", body: JSON.stringify(body) });
  }

  async dismissFromContinueWatching(): Promise<void> {
    // No-op for Simkl
  }

  async scrobble(action: "start" | "pause" | "stop", item: SyncMediaRef & { progress: number }): Promise<void> {
    if (!this.isConnected) return;
    const normProgress = item.progress <= 1.0 ? item.progress * 100 : item.progress;
    const body = item.mediaType === "movie"
      ? { movie: { ids: { tmdb: item.tmdbId } }, progress: normProgress }
      : {
          show: { ids: { tmdb: item.tmdbId } },
          episode: typeof item.episode === "number" ? { number: item.episode } : undefined,
          progress: normProgress
        };
    await this.simkl(`/scrobble/${action}`, { method: "POST", body: JSON.stringify(body) });
  }
}

export const simklClient = new SimklClient();
