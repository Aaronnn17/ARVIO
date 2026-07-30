import type { EpisodeInfo, MediaItem } from "../types";
import { getBasicItem, getSeasonEpisodes, searchMedia } from "../tmdb";
import type { MetadataResolver, ProviderPriorityConfig } from "./types";

export const tmdbResolver: MetadataResolver = {
  id: "tmdb",
  name: "TMDB",
  supportedTypes: ["movie", "tv", "anime"],

  async getDetails(id: string | number, _options?: ProviderPriorityConfig): Promise<MediaItem | null> {
    const numericId = Number(id);
    if (isNaN(numericId) || numericId <= 0) return null;

    const tvItem = await getBasicItem("tv", numericId).catch(() => null);
    if (tvItem) return tvItem;

    return getBasicItem("movie", numericId).catch(() => null);
  },

  async getEpisodes(id: string | number, seasonNumber = 1, _options?: ProviderPriorityConfig): Promise<EpisodeInfo[]> {
    const numericId = Number(id);
    if (isNaN(numericId) || numericId <= 0) return [];
    return getSeasonEpisodes(numericId, seasonNumber).catch(() => []);
  },

  async search(query: string, _options?: ProviderPriorityConfig): Promise<MediaItem[]> {
    return searchMedia(query).catch(() => []);
  }
};
