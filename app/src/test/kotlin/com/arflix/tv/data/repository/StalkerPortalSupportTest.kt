package com.arflix.tv.data.repository

import com.google.common.truth.Truth.assertThat
import com.google.gson.Gson
import org.junit.Test

class StalkerPortalSupportTest {

    private val gson = Gson()

    @Test
    fun portalIdFromChannelIdExtractsPortalSegment() {
        assertThat(StalkerPortalSupport.portalIdFromChannelId("stalker:stalker1:42"))
            .isEqualTo("stalker1")
        assertThat(StalkerPortalSupport.portalIdFromChannelId("stalker:stalker2:abc"))
            .isEqualTo("stalker2")
    }

    @Test
    fun portalIdFromChannelIdReturnsNullForNonStalkerIds() {
        assertThat(StalkerPortalSupport.portalIdFromChannelId("list_1:42")).isNull()
        assertThat(StalkerPortalSupport.portalIdFromChannelId("plain")).isNull()
    }

    @Test
    fun portalIdFromChannelIdReturnsNullWhenPortalSegmentMissing() {
        // Legacy single-portal id shape "stalker:42" has no portal segment.
        assertThat(StalkerPortalSupport.portalIdFromChannelId("stalker:42")).isNull()
    }

    @Test
    fun startsWithStalkerStillMatchesNewPrefixedIds() {
        // The existing checks rely on startsWith("stalker:") and must keep matching.
        assertThat("stalker:stalker1:42".startsWith("stalker:")).isTrue()
        assertThat("stalker:stalker2:abc".startsWith("stalker:")).isTrue()
    }

    @Test
    fun migratedPortalFromLegacyProducesPortal1() {
        val portal = StalkerPortalSupport.migratedPortalFromLegacy(
            "http://portal.example/stalker_portal/",
            "00:1A:79:12:34:56"
        )
        assertThat(portal).isNotNull()
        assertThat(portal!!.id).isEqualTo("stalker1")
        assertThat(portal.name).isEqualTo("Portal 1")
        assertThat(portal.portalUrl).isEqualTo("http://portal.example/stalker_portal")
        assertThat(portal.macAddress).isEqualTo("00:1A:79:12:34:56")
    }

    @Test
    fun migratedPortalFromLegacyReturnsNullWhenFieldsBlank() {
        assertThat(StalkerPortalSupport.migratedPortalFromLegacy("", "00:1A:79:12:34:56")).isNull()
        assertThat(StalkerPortalSupport.migratedPortalFromLegacy("http://portal", "")).isNull()
    }

    @Test
    fun migrateAndDecodeRoundTripsThroughJson() {
        val migrated = StalkerPortalSupport.migratedPortalFromLegacy(
            "http://portal.example/",
            "00:1a:79:aa:bb:cc"
        )!!
        // MAC is uppercased during migration.
        assertThat(migrated.macAddress).isEqualTo("00:1A:79:AA:BB:CC")

        val json = gson.toJson(listOf(migrated))
        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)
        assertThat(decoded).hasSize(1)
        assertThat(decoded[0].id).isEqualTo("stalker1")
        assertThat(decoded[0].portalUrl).isEqualTo("http://portal.example")
        assertThat(decoded[0].macAddress).isEqualTo("00:1A:79:AA:BB:CC")
    }

    @Test
    fun decodeStalkerPortalsPreservesMultiplePortalsAndOrder() {
        val portals = listOf(
            StalkerPortalEntry("stalker1", "Portal 1", "http://a/", "00:1A:79:11:11:11"),
            StalkerPortalEntry("stalker2", "Portal 2", "http://b/", "00:1A:79:22:22:22"),
            StalkerPortalEntry("stalker3", "Portal 3", "http://c/", "00:1A:79:33:33:33")
        )
        val json = gson.toJson(portals)
        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)
        assertThat(decoded.map { it.id })
            .containsExactly("stalker1", "stalker2", "stalker3").inOrder()
        assertThat(decoded.map { it.portalUrl })
            .containsExactly("http://a", "http://b", "http://c").inOrder()
    }

    @Test
    fun decodeStalkerPortalsCapsAtMaxPortals() {
        val portals = listOf(
            StalkerPortalEntry("stalker1", "Portal 1", "http://a/", "00:1A:79:11:11:11"),
            StalkerPortalEntry("stalker2", "Portal 2", "http://b/", "00:1A:79:22:22:22"),
            StalkerPortalEntry("stalker3", "Portal 3", "http://c/", "00:1A:79:33:33:33"),
            StalkerPortalEntry("stalker4", "Portal 4", "http://d/", "00:1A:79:44:44:44")
        )
        val json = gson.toJson(portals)
        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)
        assertThat(decoded).hasSize(3)
        assertThat(decoded.map { it.id })
            .containsExactly("stalker1", "stalker2", "stalker3").inOrder()
    }

    @Test
    fun decodeStalkerPortalsDropsEntriesWithBlankFields() {
        val portals = listOf(
            StalkerPortalEntry("stalker1", "Portal 1", "http://a/", "00:1A:79:11:11:11"),
            StalkerPortalEntry("stalker2", "Portal 2", "", "00:1A:79:22:22:22"),
            StalkerPortalEntry("stalker3", "Portal 3", "http://c/", "")
        )
        val json = gson.toJson(portals)
        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)
        assertThat(decoded).hasSize(1)
        assertThat(decoded[0].id).isEqualTo("stalker1")
    }

    @Test
    fun decodeStalkerPortalsAssignsDefaultIdAndNameWhenBlank() {
        val portals = listOf(
            StalkerPortalEntry("", "", "http://a/", "00:1A:79:11:11:11")
        )
        val json = gson.toJson(portals)
        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)
        assertThat(decoded).hasSize(1)
        assertThat(decoded[0].id).isEqualTo("stalker1")
        assertThat(decoded[0].name).isEqualTo("Portal 1")
    }

    @Test
    fun decodeStalkerPortalsReturnsEmptyForBlankOrMalformedInput() {
        assertThat(StalkerPortalSupport.decodeStalkerPortals("", maxPortals = 3)).isEmpty()
        assertThat(StalkerPortalSupport.decodeStalkerPortals("not json", maxPortals = 3)).isEmpty()
    }

    @Test
    fun multiPortalChannelIdsResolveToDistinctPortals() {
        val ids = listOf("stalker:stalker1:10", "stalker:stalker2:20", "stalker:stalker3:30")
        val portalIds = ids.mapNotNull { StalkerPortalSupport.portalIdFromChannelId(it) }
        assertThat(portalIds).containsExactly("stalker1", "stalker2", "stalker3").inOrder()
    }

    @Test
    fun playlistAndCacheKeysAreScopedPerPortal() {
        val firstId = "stalker:stalker1:10"
        val secondId = "stalker:stalker2:10"

        assertThat(StalkerPortalSupport.playlistIdFromChannelId(firstId)).isEqualTo("stalker1")
        assertThat(StalkerPortalSupport.playlistIdFromChannelId(secondId)).isEqualTo("stalker2")
        assertThat(StalkerPortalSupport.streamCacheKey(firstId, "ffmpeg http://same"))
            .isNotEqualTo(StalkerPortalSupport.streamCacheKey(secondId, "ffmpeg http://same"))
    }

    @Test
    fun nextAvailablePortalIdDoesNotReuseDeletedPortalIdentity() {
        assertThat(
            StalkerPortalSupport.nextAvailablePortalId(
                listOf("stalker1", "stalker3"),
                maxPortals = 3,
            )
        ).isEqualTo("stalker4")
    }

    @Test
    fun decodeStalkerPortalsRepairsDuplicateIds() {
        val json = gson.toJson(
            listOf(
                StalkerPortalEntry("stalker1", "A", "http://a", "00:1A:79:11:11:11"),
                StalkerPortalEntry("stalker1", "B", "http://b", "00:1A:79:22:22:22"),
            )
        )

        val decoded = StalkerPortalSupport.decodeStalkerPortals(json, maxPortals = 3)

        assertThat(decoded.map { it.id }).containsExactly("stalker1", "stalker2").inOrder()
    }

    @Test
    fun legacyChannelAndGroupKeysMigrateToPortal1() {
        assertThat(StalkerPortalSupport.migrateLegacyChannelId("stalker:42"))
            .isEqualTo("stalker:stalker1:42")
        assertThat(StalkerPortalSupport.migrateLegacyChannelId("stalker:stalker2:42"))
            .isEqualTo("stalker:stalker2:42")
        assertThat(StalkerPortalSupport.migrateLegacyPlaylistGroupKey("stalker|News"))
            .isEqualTo("stalker1|News")
    }

    @Test
    fun cloudGroupKeysKeepConfiguredStalkerPortalOrdering() {
        val normalized = StalkerPortalSupport.normalizePlaylistGroupKeys(
            listOf("stalker2|Sports", "stalker1|News", "removed|Kids"),
            validSourceIds = setOf("stalker1", "stalker2"),
        )

        assertThat(normalized).containsExactly("stalker2|Sports", "stalker1|News").inOrder()
    }

    @Test
    fun normalizeStalkerPortalEntryTrimsUrlAndUppercasesMac() {
        val portal = StalkerPortalEntry("stalker1", "Portal 1", "  http://a/  ", "  00:1a:79:aa:bb:cc  ")
        val normalized = StalkerPortalSupport.normalizeStalkerPortalEntry(portal, 0)
        assertThat(normalized).isNotNull()
        assertThat(normalized!!.portalUrl).isEqualTo("http://a")
        assertThat(normalized.macAddress).isEqualTo("00:1A:79:AA:BB:CC")
        assertThat(normalized.enabled).isTrue()
    }

    @Test
    fun normalizeStalkerPortalEntryAssignsDefaultIdAndNameByIndex() {
        val portal = StalkerPortalEntry("", "", "http://a/", "00:1A:79:AA:BB:CC")
        val normalized = StalkerPortalSupport.normalizeStalkerPortalEntry(portal, 2)
        assertThat(normalized).isNotNull()
        assertThat(normalized!!.id).isEqualTo("stalker3")
        assertThat(normalized.name).isEqualTo("Portal 3")
    }

    @Test
    fun normalizeStalkerPortalEntryReturnsNullForBlankFields() {
        assertThat(StalkerPortalSupport.normalizeStalkerPortalEntry(
            StalkerPortalEntry("stalker1", "Portal 1", "", "00:1A:79:AA:BB:CC"), 0
        )).isNull()
        assertThat(StalkerPortalSupport.normalizeStalkerPortalEntry(
            StalkerPortalEntry("stalker1", "Portal 1", "http://a/", ""), 0
        )).isNull()
    }

    @Test
    fun normalizeStalkerPortalEntryPreservesEnabledFlag() {
        val portal = StalkerPortalEntry("stalker1", "Portal 1", "http://a/", "00:1A:79:AA:BB:CC", enabled = false)
        val normalized = StalkerPortalSupport.normalizeStalkerPortalEntry(portal, 0)
        assertThat(normalized).isNotNull()
        assertThat(normalized!!.enabled).isFalse()
    }
}
