import type { EpisodeInfo, MediaItem, MediaType } from "../types";

export type MetadataProviderId = "tmdb" | "tvdb" | "anilist" | "kitsu" | "mal" | "omdb";

export interface MetadataResolver {
  id: MetadataProviderId;
  name: string;
  supportedTypes: MediaType[];

  getDetails(id: string | number, mediaType: MediaType, options?: ProviderPriorityConfig): Promise<MediaItem | null>;
  getEpisodes?(id: string | number, seasonNumber?: number, options?: ProviderPriorityConfig): Promise<EpisodeInfo[]>;
  search(query: string, mediaType: MediaType, options?: ProviderPriorityConfig): Promise<MediaItem[]>;
}


export interface ProviderPriorityConfig {
  movieProviders: MetadataProviderId[];
  tvProviders: MetadataProviderId[];
  animeProviders: MetadataProviderId[];
  customTmdbApiKey?: string;
  customTvdbApiKey?: string;
  customTvdbUserPin?: string;
}
