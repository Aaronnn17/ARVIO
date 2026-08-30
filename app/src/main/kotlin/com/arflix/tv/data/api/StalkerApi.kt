package com.arflix.tv.data.api

import com.arflix.tv.data.model.IptvChannel
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Stalker/Ministra portal API client for MAC-based IPTV authentication.
 * Converts Stalker portal channels into the same IptvChannel format as Xtream/M3U.
 */
open class StalkerApi(
    private val portalUrl: String,
    private val macAddress: String
) {
    private var apiBase: String = portalUrl.trim().trimEnd('/')
    private var apiBaseResolved = false

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()
    private val gson = Gson()
    private var token: String = ""
    private var serialNumber: String = ""

    private val baseHeaders: Map<String, String>
        get() = mapOf(
            "User-Agent" to "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3",
            "Cookie" to "mac=$macAddress; stb_lang=en; timezone=Europe/London",
            "X-User-Agent" to "Model: MAG250; Link: WiFi",
            "Authorization" to "Bearer $token"
        )

    /** Step 1: Handshake to get auth token */
    suspend fun handshake(): Boolean {
        return try {
            if (!apiBaseResolved) {
                resolveApiBase()
            }
            val url = "$apiBase/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            val response = doGet(url)
            val parsed = gson.fromJson(response, StalkerHandshakeResponse::class.java)
            token = parsed?.js?.token ?: return false
            true
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e

            System.err.println("[Stalker] Handshake failed: ${e.message}")
            false
        }
    }

    /**
     * Try candidate portal base paths until one responds to the handshake with
     * a valid token. HTML 404 pages (e.g. served on /c/ portal URLs) or empty
     * bodies must not stop the probing early.
     * Order: / (root), /stalker_portal, /portal, /c
     */
    private suspend fun resolveApiBase() {
        val cleanPortal = portalUrl.trim().trimEnd('/')
        // Common portals serve the UI under /c/ while the API lives at the
        // root or a root subpath, so probe both the raw URL and its /c-stripped root.
        val root = cleanPortal.removeSuffix("/c").removeSuffix("/")
        val candidates = listOf(
            cleanPortal,
            root,
            "$root/stalker_portal",
            "$root/portal",
            "$root/ministra"
        ).distinct()
        for (base in candidates) {
            try {
                val url = "$base/server/load.php?type=stb&action=handshake"
                val response = doGet(url)
                val probeToken = try {
                    gson.fromJson(response, StalkerHandshakeResponse::class.java)?.js?.token
                } catch (_: Exception) { null }
                if (!probeToken.isNullOrBlank()) {
                    apiBase = base
                    token = probeToken
                    apiBaseResolved = true
                    return
                }
            } catch (e: Exception) {
                // continue to next candidate
            }
        }
        // Fallback to root
        apiBase = cleanPortal
        apiBaseResolved = true
    }

    /** Step 2: Get profile (validates the connection) */
    suspend fun getProfile(): Boolean {
        return try {
            val url = "$apiBase/server/load.php?type=stb&action=get_profile&JsHttpRequest=1-xml"
            val response = doGet(url)
            response.contains("\"id\"")
        } catch (_: Exception) { false }
    }

    /** Step 3: Get all channels */
    suspend fun getChannels(): List<IptvChannel> {
        val channels = mutableListOf<IptvChannel>()
        val seenChannelIds = HashSet<String>()
        try {
            // Get genres first for group names
            val genreUrl = "$apiBase/server/load.php?type=itv&action=get_genres&JsHttpRequest=1-xml"
            val genreResponse = doGet(genreUrl)
            val genres = gson.fromJson(genreResponse, StalkerGenreResponse::class.java)
            val genreMap = genres?.js?.mapNotNull { g -> g.id?.let { it to (g.title ?: "Unknown") } }?.toMap() ?: emptyMap()

            // Get all channels page by page
            var page = 1
            var hasMore = true
            while (hasMore) {
                val url = "$apiBase/server/load.php?type=itv&action=get_all_channels&p=$page&JsHttpRequest=1-xml"
                val response = doGet(url)
                val parsed = gson.fromJson(response, StalkerChannelResponse::class.java)
                val data = parsed?.js?.data ?: break

                var newChannelIdCount = 0
                for (ch in data) {
                    val channelId = ch.id?.toString() ?: continue
                    if (!seenChannelIds.add(channelId)) continue
                    newChannelIdCount++
                    val streamCmd = ch.cmd ?: continue
                    val groupName = ch.tvGenreId?.let { genreMap[it] } ?: "Uncategorized"
                    channels.add(
                        IptvChannel(
                            id = channelId,
                            name = ch.name ?: "Unknown",
                            logo = ch.logo,
                            group = groupName,
                            streamUrl = streamCmd // Will be resolved via create_link before playback
                        )
                    )
                }

                val totalItems = parsed.js?.totalItems ?: 0
                val maxPageItems = (parsed.js?.maxPageItems ?: 20).coerceAtLeast(1)
                // Some portals ignore pagination and return all channels in every response.
                // Stop when a page contains no new IDs as well as when one response
                // already contains the complete channel list.
                hasMore = newChannelIdCount > 0 &&
                    page * maxPageItems < totalItems &&
                    data.size < totalItems
                page++
            }

        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e

            System.err.println("[Stalker] Get channels failed: ${e.message}")
        }
        return channels
    }

    /**
     * Fetch the portal's now/next EPG data for all channels.
     * [date] uses `YYYY-MM-DD`; blank means "today" on the server side.
     *
     * Tries `type=epg&action=get_simple_data_table` first (lightweight, one flat
     * list). Some Stalker/Ministra portal builds don't implement the `epg` type
     * handler at all (confirmed on-device: 0-byte response, while `itv`/`stb`
     * actions on the same portal work fine) - for those, falls back to
     * `type=itv&action=get_epg_info`, which some portals return as a flat list
     * like the first action and others as an object keyed by channel id.
     */
    suspend fun getEpg(date: String = ""): List<StalkerEpgProgram> {
        val dateParam = if (date.isBlank()) "" else "&date=${java.net.URLEncoder.encode(date, "UTF-8")}"
        val simpleTable = fetchSimpleDataTableEpg(dateParam)
        if (simpleTable.isNotEmpty()) return simpleTable
        return fetchEpgInfoFallback(dateParam)
    }

    private fun fetchSimpleDataTableEpg(dateParam: String): List<StalkerEpgProgram> {
        return try {
            val url = "$apiBase/server/load.php?type=epg&action=get_simple_data_table&ch_id=all$dateParam&JsHttpRequest=1-xml"
            val response = doGet(url)
            System.err.println("[Stalker] get_simple_data_table raw response (${response.length} chars): ${response.take(500)}")
            val parsed = gson.fromJson(response, StalkerEpgResponse::class.java)
            parsed?.js.orEmpty().filterNotNull()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            System.err.println("[Stalker] get_simple_data_table failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * `get_epg_info` response shape varies by portal build. Confirmed on-device
     * against two different portals: `{"js":{"data":[]}}` (nothing available) and
     * `{"js":{"data":{"<ch_id>":[{...program...}], ...}}}` (real data, one entry
     * per channel id, ~tens of MB for a multi-thousand-channel portal). Some
     * builds may skip the "data" wrapper and put the array/object directly under
     * "js" (matching the get_simple_data_table shape) - both are handled.
     */
    private fun fetchEpgInfoFallback(dateParam: String): List<StalkerEpgProgram> {
        return try {
            val url = "$apiBase/server/load.php?type=itv&action=get_epg_info$dateParam&JsHttpRequest=1-xml"
            val response = doGet(url)
            System.err.println("[Stalker] get_epg_info raw response (${response.length} chars): ${response.take(800)}")

            val jsElement = runCatching {
                com.google.gson.JsonParser.parseString(response).asJsonObject.get("js")
            }.getOrNull() ?: return emptyList()

            // Unwrap the "data" wrapper when present; otherwise treat "js" itself
            // as the array/object to parse (older/other portal builds).
            val dataElement = if (jsElement.isJsonObject && jsElement.asJsonObject.has("data")) {
                jsElement.asJsonObject.get("data")
            } else {
                jsElement
            }

            when {
                dataElement.isJsonArray -> {
                    val listType = com.google.gson.reflect.TypeToken.getParameterized(
                        List::class.java, StalkerEpgProgram::class.java
                    ).type
                    runCatching {
                        gson.fromJson<List<StalkerEpgProgram?>>(dataElement, listType)
                    }.getOrNull().orEmpty().filterNotNull()
                }
                dataElement.isJsonObject -> {
                    val mapType = com.google.gson.reflect.TypeToken.getParameterized(
                        Map::class.java,
                        String::class.java,
                        com.google.gson.reflect.TypeToken.getParameterized(List::class.java, StalkerEpgProgram::class.java).type
                    ).type
                    val asMap = runCatching {
                        gson.fromJson<Map<String, List<StalkerEpgProgram?>?>>(dataElement, mapType)
                    }.getOrNull().orEmpty()
                    asMap.flatMap { (channelId, programs) ->
                        programs.orEmpty().filterNotNull().map { program ->
                            if (program.chId.isNullOrBlank()) program.copy(chId = channelId) else program
                        }
                    }
                }
                else -> emptyList()
            }
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            System.err.println("[Stalker] get_epg_info failed: ${e.message}")
            emptyList()
        }
    }

    /** Resolve a channel's cmd to a playable stream URL */
    suspend fun resolveStreamUrl(cmd: String): String? {
        return try {
            val encodedCmd = java.net.URLEncoder.encode(cmd, "UTF-8")
            val url = "$apiBase/server/load.php?type=itv&action=create_link&cmd=$encodedCmd&forced_storage=undefined&disable_ad=0&JsHttpRequest=1-xml"
            val response = doGet(url)
            val parsed = gson.fromJson(response, StalkerLinkResponse::class.java)
            parsed?.js?.cmd?.replace("ffmpeg ", "")?.trim()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e

            System.err.println("[Stalker] Resolve stream failed: ${e.message}")
            null
        }
    }

    open fun doGet(url: String): String {
        val builder = Request.Builder().url(url)
        baseHeaders.forEach { (k, v) -> builder.addHeader(k, v) }
        val response = client.newCall(builder.build()).execute()
        return response.body?.string() ?: ""
    }

    // ── Response models ──

    data class StalkerHandshakeResponse(val js: StalkerToken?)
    data class StalkerToken(val token: String?)

    data class StalkerGenreResponse(val js: List<StalkerGenre>?)
    data class StalkerGenre(val id: String?, val title: String?)

    data class StalkerChannelResponse(val js: StalkerChannelData?)
    data class StalkerChannelData(
        val data: List<StalkerChannel>?,
        @SerializedName("total_items") val totalItems: Int?,
        @SerializedName("max_page_items") val maxPageItems: Int?
    )
    data class StalkerChannel(
        val id: Int?,
        val name: String?,
        val logo: String?,
        val cmd: String?,
        @SerializedName("tv_genre_id") val tvGenreId: String?
    )

    data class StalkerLinkResponse(val js: StalkerLink?)
    data class StalkerLink(val cmd: String?)

    data class StalkerEpgResponse(val js: List<StalkerEpgProgram?>?)

    /** Field names vary by portal software/version, hence the alternates. */
    data class StalkerEpgProgram(
        @SerializedName(value = "ch_id", alternate = ["channel_id"]) val chId: String?,
        @SerializedName(value = "name", alternate = ["title"]) val name: String?,
        @SerializedName(value = "descr", alternate = ["description"]) val descr: String?,
        @SerializedName(value = "start_timestamp", alternate = ["start"]) val startTimestamp: String?,
        @SerializedName(value = "stop_timestamp", alternate = ["end_timestamp", "end"]) val stopTimestamp: String?
    )
}
