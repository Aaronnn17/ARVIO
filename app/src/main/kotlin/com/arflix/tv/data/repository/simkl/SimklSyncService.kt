package com.arflix.tv.data.repository.simkl

import com.arflix.tv.data.api.SimklAddToListBody
import com.arflix.tv.data.api.SimklAddToListMovie
import com.arflix.tv.data.api.SimklAddToListShow
import com.arflix.tv.data.api.SimklAllItemsResponse
import com.arflix.tv.data.api.SimklApi
import com.arflix.tv.data.api.SimklDeleteFromListBody
import com.arflix.tv.data.api.SimklEpisodeRef
import com.arflix.tv.data.api.SimklIds
import com.arflix.tv.data.api.SimklMovieRef
import com.arflix.tv.data.api.SimklSeasonRef
import com.arflix.tv.data.api.SimklShowRef
import com.arflix.tv.data.api.SimklSyncHistoryBody
import com.arflix.tv.data.model.MediaItem
import com.arflix.tv.data.model.MediaType
import com.arflix.tv.util.AppLogger
import com.arflix.tv.util.Constants
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SimklSyncService @Inject constructor(
    private val simklApi: SimklApi,
    private val authManager: SimklAuthManager
) {
    private val clientId: String get() = Constants.SIMKL_CLIENT_ID

    private val syncMutex = Mutex()
    private var lastActivityTimestamp: String? = null
    private var lastActivityCheckTime: Long = 0L

    private val cachedWatchedMovies = mutableSetOf<Int>()
    private val cachedWatchedEpisodes = mutableSetOf<String>()
    private val cachedWatchlist = mutableMapOf<Pair<MediaType, Int>, MediaItem>()

    /**
     * Follows official Simkl sync guidelines:
     * Phase 1: Fetch libraries separately and sequentially without date_from on initial load.
     * Phase 2: Check /sync/activities first. If timestamp changed, fetch delta using /sync/all-items/?date_from=...
     * Throttles background checks to once every 15 minutes unless forced.
     */
    suspend fun syncIfNeeded(force: Boolean = false) = syncMutex.withLock {
        val token = authManager.getAccessToken() ?: return@withLock
        val authHeader = "Bearer $token"

        val now = System.currentTimeMillis()
        if (!force && (now - lastActivityCheckTime < 15 * 60 * 1000L) && lastActivityTimestamp != null) {
            return@withLock
        }

        try {
            val activities = simklApi.getActivities(authHeader, clientId)
            lastActivityCheckTime = now
            val currentActivityDate = activities.all ?: activities.movies?.all ?: activities.shows?.all

            if (lastActivityTimestamp == null) {
                // PHASE 1: Initial Sync Strategy (fetch sequentially)
                AppLogger.d("SimklSyncService", "Running Phase 1 Initial Sync sequentially")
                cachedWatchedMovies.clear()
                cachedWatchedEpisodes.clear()
                cachedWatchlist.clear()

                val moviesRes = simklApi.getAllItemsByType(authHeader, clientId, "movies")
                processMoviesResponse(moviesRes)

                delay(200)
                val showsRes = simklApi.getAllItemsByType(authHeader, clientId, "shows")
                processShowsResponse(showsRes)

                delay(200)
                val animeRes = simklApi.getAllItemsByType(authHeader, clientId, "anime")
                processShowsResponse(animeRes)

                lastActivityTimestamp = currentActivityDate
            } else if (currentActivityDate != null && currentActivityDate != lastActivityTimestamp) {
                // PHASE 2: Continuous Sync Loop (delta sync with date_from)
                AppLogger.d("SimklSyncService", "Running Phase 2 Delta Sync with date_from=$lastActivityTimestamp")
                val deltaRes = simklApi.getAllItems(authHeader, clientId, dateFrom = lastActivityTimestamp)
                processMoviesResponse(deltaRes)
                processShowsResponse(deltaRes)

                lastActivityTimestamp = currentActivityDate
            } else {
                AppLogger.d("SimklSyncService", "Simkl activities unchanged ($currentActivityDate). Skipping sync.")
            }
        } catch (e: Exception) {
            AppLogger.e("SimklSyncService", "Error during Simkl sync: ${e.message}")
        }
    }

    private fun processMoviesResponse(response: SimklAllItemsResponse) {
        response.movies?.forEach { movieItem ->
            val tmdbId = movieItem.movie?.ids?.tmdb ?: return@forEach
            val status = movieItem.status
            if (status == "completed" || status == "watching") {
                cachedWatchedMovies.add(tmdbId)
            }
            if (status == "plantowatch") {
                cachedWatchlist[MediaType.MOVIE to tmdbId] = MediaItem(
                    id = tmdbId,
                    title = movieItem.movie.title.orEmpty(),
                    mediaType = MediaType.MOVIE
                )
            } else if (status != null) {
                cachedWatchlist.remove(MediaType.MOVIE to tmdbId)
            }
        }
    }

    private fun processShowsResponse(response: SimklAllItemsResponse) {
        val allShows = (response.shows.orEmpty() + response.anime.orEmpty())
        allShows.forEach { showItem ->
            val showTmdb = showItem.show?.ids?.tmdb ?: return@forEach
            val status = showItem.status
            if (status == "plantowatch") {
                cachedWatchlist[MediaType.TV to showTmdb] = MediaItem(
                    id = showTmdb,
                    title = showItem.show.title.orEmpty(),
                    mediaType = MediaType.TV
                )
            } else if (status != null) {
                cachedWatchlist.remove(MediaType.TV to showTmdb)
            }
            showItem.seasons?.forEach { season ->
                season.episodes.forEach { episode ->
                    cachedWatchedEpisodes.add("${showTmdb}_S${season.number}_E${episode.number}")
                }
            }
        }
    }

    suspend fun getWatchedMovies(): Set<Int> {
        syncIfNeeded()
        return cachedWatchedMovies.toSet()
    }

    suspend fun getWatchedEpisodes(): Set<String> {
        syncIfNeeded()
        return cachedWatchedEpisodes.toSet()
    }

    suspend fun getWatchlistItems(): List<MediaItem> {
        syncIfNeeded()
        return cachedWatchlist.values.toList()
    }

    suspend fun addToWatchlist(mediaType: MediaType, tmdbId: Int): Boolean {
        val token = authManager.getAccessToken() ?: return false
        val authHeader = "Bearer $token"
        val body = if (mediaType == MediaType.MOVIE) {
            SimklAddToListBody(
                movies = listOf(SimklAddToListMovie(to = "plantowatch", ids = SimklIds(tmdb = tmdbId)))
            )
        } else {
            SimklAddToListBody(
                shows = listOf(SimklAddToListShow(to = "plantowatch", ids = SimklIds(tmdb = tmdbId)))
            )
        }
        return try {
            val res = simklApi.addToList(authHeader, clientId, body)
            if (res.isSuccessful) {
                cachedWatchlist[mediaType to tmdbId] = MediaItem(id = tmdbId, title = "", mediaType = mediaType)
                lastActivityCheckTime = 0L // Request activity refresh on next check
                true
            } else {
                false
            }
        } catch (e: Exception) {
            AppLogger.e("SimklSyncService", "Error adding to watchlist: ${e.message}")
            false
        }
    }

    suspend fun removeFromWatchlist(mediaType: MediaType, tmdbId: Int): Boolean {
        val token = authManager.getAccessToken() ?: return false
        val authHeader = "Bearer $token"
        val body = if (mediaType == MediaType.MOVIE) {
            SimklDeleteFromListBody(movies = listOf(SimklMovieRef(ids = SimklIds(tmdb = tmdbId))))
        } else {
            SimklDeleteFromListBody(shows = listOf(SimklShowRef(ids = SimklIds(tmdb = tmdbId))))
        }
        return try {
            val res = simklApi.deleteFromList(authHeader, clientId, body)
            if (res.isSuccessful) {
                cachedWatchlist.remove(mediaType to tmdbId)
                lastActivityCheckTime = 0L
                true
            } else {
                false
            }
        } catch (e: Exception) {
            AppLogger.e("SimklSyncService", "Error removing from watchlist: ${e.message}")
            false
        }
    }

    suspend fun markWatched(mediaType: MediaType, tmdbId: Int, season: Int? = null, episode: Int? = null): Boolean {
        val token = authManager.getAccessToken() ?: return false
        val authHeader = "Bearer $token"
        val body = if (mediaType == MediaType.MOVIE) {
            SimklSyncHistoryBody(movies = listOf(SimklMovieRef(ids = SimklIds(tmdb = tmdbId))))
        } else {
            SimklSyncHistoryBody(
                shows = listOf(
                    SimklShowRef(
                        ids = SimklIds(tmdb = tmdbId),
                        seasons = if (season != null && episode != null) {
                            listOf(SimklSeasonRef(number = season, episodes = listOf(SimklEpisodeRef(number = episode))))
                        } else null
                    )
                )
            )
        }
        return try {
            val res = simklApi.addToHistory(authHeader, clientId, body, allowRewatch = "yes")
            if (res.isSuccessful) {
                if (mediaType == MediaType.MOVIE) {
                    cachedWatchedMovies.add(tmdbId)
                } else if (season != null && episode != null) {
                    cachedWatchedEpisodes.add("${tmdbId}_S${season}_E${episode}")
                }
                lastActivityCheckTime = 0L
                true
            } else {
                false
            }
        } catch (e: Exception) {
            AppLogger.e("SimklSyncService", "Error marking watched: ${e.message}")
            false
        }
    }

    suspend fun markUnwatched(mediaType: MediaType, tmdbId: Int, season: Int? = null, episode: Int? = null): Boolean {
        val token = authManager.getAccessToken() ?: return false
        val authHeader = "Bearer $token"
        val body = if (mediaType == MediaType.MOVIE) {
            SimklSyncHistoryBody(movies = listOf(SimklMovieRef(ids = SimklIds(tmdb = tmdbId))))
        } else {
            SimklSyncHistoryBody(
                shows = listOf(
                    SimklShowRef(
                        ids = SimklIds(tmdb = tmdbId),
                        seasons = if (season != null && episode != null) {
                            listOf(SimklSeasonRef(number = season, episodes = listOf(SimklEpisodeRef(number = episode))))
                        } else null
                    )
                )
            )
        }
        return try {
            val res = simklApi.removeFromHistory(authHeader, clientId, body)
            if (res.isSuccessful) {
                if (mediaType == MediaType.MOVIE) {
                    cachedWatchedMovies.remove(tmdbId)
                } else if (season != null && episode != null) {
                    cachedWatchedEpisodes.remove("${tmdbId}_S${season}_E${episode}")
                }
                lastActivityCheckTime = 0L
                true
            } else {
                false
            }
        } catch (e: Exception) {
            AppLogger.e("SimklSyncService", "Error marking unwatched: ${e.message}")
            false
        }
    }
}
