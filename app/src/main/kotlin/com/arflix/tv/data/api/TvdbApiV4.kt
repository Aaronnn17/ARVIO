package com.arflix.tv.data.api

import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface TvdbApiV4 {

    @POST("login")
    suspend fun login(
        @Body request: TvdbLoginRequest
    ): TvdbResponse<TvdbLoginData>

    @GET("series/{id}/extended")
    suspend fun getSeriesExtended(
        @Header("Authorization") bearerToken: String,
        @Path("id") id: Int
    ): TvdbResponse<TvdbSeriesData>

    @GET("series/{id}/episodes/{seasonType}")
    suspend fun getSeriesEpisodes(
        @Header("Authorization") bearerToken: String,
        @Path("id") id: Int,
        @Path("seasonType") seasonType: String = "default",
        @Query("page") page: Int = 0
    ): TvdbResponse<TvdbEpisodesData>

    @GET("search")
    suspend fun search(
        @Header("Authorization") bearerToken: String,
        @Query("query") query: String,
        @Query("type") type: String? = null
    ): TvdbResponse<List<TvdbSearchItem>>
}

data class TvdbLoginRequest(
    val apikey: String,
    val pin: String? = null
)

data class TvdbResponse<T>(
    val status: String,
    val data: T?
)

data class TvdbLoginData(
    val token: String
)

data class TvdbSeriesData(
    val id: Int,
    val name: String?,
    val overview: String?,
    val image: String?,
    val firstAired: String?,
    val lastAired: String?,
    val status: TvdbStatus?,
    val score: Double?,
    val genres: List<TvdbGenre>?
)

data class TvdbStatus(
    val name: String?
)

data class TvdbGenre(
    val id: Int,
    val name: String?
)

data class TvdbEpisodesData(
    val series: TvdbSeriesData?,
    val episodes: List<TvdbEpisodeItem>?
)

data class TvdbEpisodeItem(
    val id: Int,
    val seriesId: Int?,
    val name: String?,
    val overview: String?,
    val image: String?,
    val number: Int?,
    val seasonNumber: Int?,
    val aired: String?,
    val runtime: Int?
)

data class TvdbSearchItem(
    val tvdb_id: String?,
    val name: String?,
    val overview: String?,
    val image_url: String?,
    val type: String?,
    val year: String?
)
