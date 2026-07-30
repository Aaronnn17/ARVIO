import type { EpisodeInfo, MediaItem, MediaType } from "../types";
import { aniListResolver } from "./anilist";
import { tvdbResolver } from "./tvdb";
import { tmdbResolver } from "./tmdbResolver";
import type { MetadataProviderId, MetadataResolver, ProviderPriorityConfig } from "./types";

export class MetadataDispatcher {
  private static resolvers: Record<string, MetadataResolver> = {
    anilist: aniListResolver,
    tvdb: tvdbResolver,
    tmdb: tmdbResolver
  };

  static registerResolver(resolver: MetadataResolver) {
    this.resolvers[resolver.id] = resolver;
  }

  static getPriorityList(type: MediaType, config?: ProviderPriorityConfig): MetadataProviderId[] {
    if (type === "anime") {
      return config?.animeProviders ?? ["anilist", "tvdb", "tmdb"];
    }
    if (type === "tv") {
      return config?.tvProviders ?? ["tvdb", "tmdb"];
    }
    return config?.movieProviders ?? ["tmdb"];
  }

  static async getDetails(
    id: string | number,
    type: MediaType,
    config?: ProviderPriorityConfig
  ): Promise<MediaItem | null> {
    const priority = this.getPriorityList(type, config);

    for (const providerId of priority) {
      const resolver = this.resolvers[providerId];
      if (!resolver) continue;

      const result = await resolver.getDetails(id, config);
      if (result) {
        return result;
      }
    }
    return null;
  }

  static async getEpisodes(
    id: string | number,
    type: MediaType,
    seasonNumber = 1,
    config?: ProviderPriorityConfig
  ): Promise<EpisodeInfo[]> {
    const priority = this.getPriorityList(type, config);

    for (const providerId of priority) {
      const resolver = this.resolvers[providerId];
      if (!resolver || !resolver.getEpisodes) continue;

      const episodes = await resolver.getEpisodes(id, seasonNumber, config);
      if (episodes && episodes.length > 0) {
        return episodes;
      }
    }
    return [];
  }

  static async search(
    query: string,
    type: MediaType,
    config?: ProviderPriorityConfig
  ): Promise<MediaItem[]> {
    const priority = this.getPriorityList(type, config);

    for (const providerId of priority) {
      const resolver = this.resolvers[providerId];
      if (!resolver) continue;

      const results = await resolver.search(query, config);
      if (results && results.length > 0) {
        return results;
      }
    }

    return [];
  }
}
