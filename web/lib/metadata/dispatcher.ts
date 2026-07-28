import type { MediaItem, MediaType } from "../types";
import { aniListResolver } from "./anilist";
import { tvdbResolver } from "./tvdb";
import type { MetadataProviderId, MetadataResolver, ProviderPriorityConfig } from "./types";

export class MetadataDispatcher {
  private static resolvers: Record<string, MetadataResolver> = {
    anilist: aniListResolver,
    tvdb: tvdbResolver
  };

  static registerResolver(resolver: MetadataResolver) {
    this.resolvers[resolver.id] = resolver;
  }

  static getPriorityList(type: MediaType, config?: ProviderPriorityConfig): MetadataProviderId[] {
    if (type === ("anime" as any)) {
      return config?.animeProviders ?? ["anilist", "tvdb", "tmdb" as any];
    }
    if (type === "tv") {
      return config?.tvProviders ?? ["tvdb", "tmdb" as any];
    }
    return config?.movieProviders ?? ["tmdb" as any];
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
