package com.arflix.tv.data.repository

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * Pure helpers for the Stalker multi-portal model. Kept dependency-free so they
 * can be unit-tested without an Android context.
 */
internal object StalkerPortalSupport {

    private val gson = Gson()

    /**
     * Channel ids use the `stalker:<portalId>:<origId>` shape. Returns the
     * portal id segment, or null when the id is not a Stalker channel or the
     * portal segment is missing.
     */
    fun portalIdFromChannelId(channelId: String): String? {
        if (!channelId.startsWith("stalker:")) return null
        val afterPrefix = channelId.removePrefix("stalker:")
        val portalId = afterPrefix.substringBefore(':', missingDelimiterValue = "")
        return portalId.takeIf { it.isNotBlank() }
    }

    fun normalizeStalkerPortalEntry(
        portal: StalkerPortalEntry,
        index: Int
    ): StalkerPortalEntry? {
        val portalUrl = runCatching { portal.portalUrl }.getOrNull().orEmpty().trim().trimEnd('/')
        val macAddress = runCatching { portal.macAddress }.getOrNull().orEmpty().trim().uppercase()
        if (portalUrl.isBlank() || macAddress.isBlank()) return null
        return StalkerPortalEntry(
            id = runCatching { portal.id }.getOrNull().orEmpty().trim().ifBlank { "stalker${index + 1}" },
            name = runCatching { portal.name }.getOrNull().orEmpty().trim().ifBlank { "Portal ${index + 1}" },
            portalUrl = portalUrl,
            macAddress = macAddress,
            enabled = runCatching { portal.enabled }.getOrDefault(true)
        )
    }

    fun decodeStalkerPortals(raw: String, maxPortals: Int): List<StalkerPortalEntry> {
        if (raw.isBlank()) return emptyList()
        return runCatching {
            val type = TypeToken.getParameterized(List::class.java, StalkerPortalEntry::class.java).type
            gson.fromJson<List<StalkerPortalEntry>>(raw, type)
                ?.mapIndexed { index, portal -> normalizeStalkerPortalEntry(portal, index) }
                ?.filterNotNull()
                ?.take(maxPortals)
                ?: emptyList()
        }.getOrDefault(emptyList())
    }

    /**
     * Builds the migrated Portal 1 entry from legacy single-portal fields.
     */
    fun migratedPortalFromLegacy(portalUrl: String, macAddress: String): StalkerPortalEntry? {
        val url = portalUrl.trim().trimEnd('/')
        val mac = macAddress.trim().uppercase()
        if (url.isBlank() || mac.isBlank()) return null
        return StalkerPortalEntry(
            id = "stalker1",
            name = "Portal 1",
            portalUrl = url,
            macAddress = mac
        )
    }
}
