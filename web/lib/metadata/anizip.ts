export interface AniZipMapping {
  anilistId: number;
  malId?: number;
  tvdbId?: number;
  tmdbId?: number;
  imdbId?: string;
  episodeOffset: number;
}

export async function fetchAniZipMapping(anilistId: number): Promise<AniZipMapping | null> {
  try {
    const res = await fetch(`https://api.ani.zip/mappings?anilist_id=${anilistId}`);
    if (!res.ok) return null;

    const data = await res.json();
    const mappings = data.mappings;
    if (!mappings) return null;

    return {
      anilistId,
      malId: mappings.mal_id,
      tvdbId: mappings.thetvdb_id,
      tmdbId: mappings.themoviedb_id,
      imdbId: mappings.imdb_id,
      episodeOffset: mappings.episodeOffset ?? 0
    };
  } catch {
    return null;
  }
}
