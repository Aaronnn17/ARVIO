package com.arflix.tv.data.api

import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.POST

interface AniListApi {

    @POST("/")
    suspend fun postQuery(
        @Body request: AniListGraphQLRequest
    ): AniListGraphQLResponse
}

data class AniListGraphQLRequest(
    val query: String,
    val variables: Map<String, Any?> = emptyMap()
)

data class AniListGraphQLResponse(
    val data: AniListDataPayload?
)

data class AniListDataPayload(
    @SerializedName("Media") val media: AniListMedia?,
    @SerializedName("Page") val page: AniListPagePayload?
)

data class AniListPagePayload(
    val media: List<AniListMedia>?
)

data class AniListMedia(
    val id: Int,
    val idMal: Int?,
    val title: AniListTitle?,
    val description: String?,
    val bannerImage: String?,
    val coverImage: AniListCoverImage?,
    val format: String?,
    val status: String?,
    val episodes: Int?,
    val duration: Int?,
    val averageScore: Int?,
    val meanScore: Int?,
    val popularity: Int?,
    val genres: List<String>?,
    val startDate: AniListDate?,
    val endDate: AniListDate?,
    val season: String?,
    val seasonYear: Int?,
    val studios: AniListStudiosPayload?
)

data class AniListTitle(
    val romaji: String?,
    val english: String?,
    val native: String?
) {
    fun userPreferredTitle(): String = english ?: romaji ?: native ?: ""
}

data class AniListCoverImage(
    val extraLarge: String?,
    val large: String?,
    val medium: String?,
    val color: String?
)

data class AniListDate(
    val year: Int?,
    val month: Int?,
    val day: Int?
)

data class AniListStudiosPayload(
    val nodes: List<AniListStudioNode>?
)

data class AniListStudioNode(
    val id: Int,
    val name: String,
    val isAnimationStudio: Boolean
)
