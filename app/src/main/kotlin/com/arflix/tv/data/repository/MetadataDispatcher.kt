package com.arflix.tv.data.repository

import com.arflix.tv.data.api.AniListApi
import com.arflix.tv.data.api.AniListGraphQLRequest
import com.arflix.tv.data.api.AniListMedia
import com.arflix.tv.data.api.TmdbApi
import com.arflix.tv.data.api.TvdbApiV4
import com.arflix.tv.util.AppLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MetadataDispatcher @Inject constructor(
    private val tmdbApi: TmdbApi,
    private val aniListApi: AniListApi,
    private val tvdbApiV4: TvdbApiV4
) {
    private val TAG = "MetadataDispatcher"

    suspend fun getAnimeDetails(query: String): AniListMedia? = withContext(Dispatchers.IO) {
        try {
            val graphqlQuery = """
                query (${'$'}search: String!) {
                  Media(search: ${'$'}search, type: ANIME) {
                    id
                    idMal
                    title { romaji english native }
                    description
                    bannerImage
                    coverImage { extraLarge large medium color }
                    format
                    status
                    episodes
                    duration
                    averageScore
                    popularity
                    genres
                    season
                    seasonYear
                    studios(isMain: true) { nodes { id name isAnimationStudio } }
                  }
                }
            """.trimIndent()

            val request = AniListGraphQLRequest(
                query = graphqlQuery,
                variables = mapOf("search" to query)
            )

            val response = aniListApi.postQuery(request)
            response.data?.media
        } catch (e: Exception) {
            AppLogger.e(TAG, "AniList fetch failed for query: $query", e)
            null
        }
    }

    suspend fun getTvdbSeries(tvdbId: Int, customApiKey: String? = null): com.arflix.tv.data.api.TvdbSeriesData? = withContext(Dispatchers.IO) {
        val keyToUse = customApiKey?.trim().orEmpty()
        if (keyToUse.isEmpty()) {
            // TVDB disabled unless user enters a custom API key
            return@withContext null
        }
        try {
            val loginRes = tvdbApiV4.login(com.arflix.tv.data.api.TvdbLoginRequest(apikey = keyToUse))
            val token = loginRes.data?.token ?: return@withContext null

            val res = tvdbApiV4.getSeriesExtended("Bearer $token", tvdbId)
            res.data
        } catch (e: Exception) {
            AppLogger.e(TAG, "TVDB series fetch failed for ID: $tvdbId", e)
            null
        }
    }
}
