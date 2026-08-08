export interface AniZipEpisodeMap {
  season?: number;
  episode?: number;
}

export interface AniZipMapping {
  anilistId: number;
  malId?: number;
  tvdbId?: number;
  tmdbId?: number;
  imdbId?: string;
  season?: number;
  episodeOffset: number;
  episodeMap?: Record<string, AniZipEpisodeMap>;
}

export async function fetchAniZipMapping(anilistId: number): Promise<AniZipMapping | null> {
  try {
    const res = await fetch(`https://api.ani.zip/mappings?anilist_id=${anilistId}`);
    if (!res.ok) return null;

    const data = await res.json();
    const mappings = data.mappings;
    if (!mappings) return null;

    const episodeMap: Record<string, AniZipEpisodeMap> = {};
    if (data.episodes && typeof data.episodes === "object") {
      for (const [epNum, epInfo] of Object.entries<any>(data.episodes)) {
        const parsedSeason = epInfo.seasonNumber ?? epInfo.tvdbSeason ?? epInfo.season;
        const parsedEpisode = epInfo.episodeNumber ?? epInfo.tvdbEpisode ?? (typeof epInfo.episode === "number" ? epInfo.episode : !isNaN(Number(epInfo.episode)) ? Number(epInfo.episode) : undefined);

        episodeMap[epNum] = {
          season: typeof parsedSeason === "number" ? parsedSeason : undefined,
          episode: typeof parsedEpisode === "number" ? parsedEpisode : undefined
        };
      }
    }


    return {
      anilistId,
      malId: mappings.mal_id,
      tvdbId: mappings.thetvdb_id,
      tmdbId: mappings.themoviedb_id,
      imdbId: mappings.imdb_id,
      season: mappings.season ?? 1,
      episodeOffset: mappings.episodeOffset ?? 0,
      episodeMap
    };
  } catch {
    return null;
  }
}

/**
 * Converts an AniList episode number to the corresponding TMDB/TVDB Season and Episode number.
 */
export function convertAniListToTmdbEpisode(
  mapping: AniZipMapping,
  aniListEpisodeNumber: number
): { season: number; episode: number } {
  // 1. Direct episode map lookup if available
  const mapped = mapping.episodeMap?.[String(aniListEpisodeNumber)];
  if (typeof mapped?.season === "number" && typeof mapped?.episode === "number") {
    return { season: mapped.season, episode: mapped.episode };
  }

  // 2. Calculated offset fallback
  const season = mapping.season ?? 1;
  const calculatedEpisode = Math.max(1, aniListEpisodeNumber - mapping.episodeOffset);

  return { season, episode: calculatedEpisode };
}
