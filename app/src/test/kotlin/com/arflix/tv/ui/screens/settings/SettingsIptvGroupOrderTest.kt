package com.arflix.tv.ui.screens.settings

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SettingsIptvGroupOrderTest {

    @Test
    fun staleSavedGroupLabelsCannotReappearAfterProviderRefresh() {
        val ordered = orderedIptvGroups(
            playlistId = "list_1",
            availableGroups = listOf("Entertainment", "Kids", "Movies"),
            groupOrder = listOf("list_1|[B] Kids", "list_1|Movies"),
        )

        assertThat(ordered).containsExactly("Movies", "Entertainment", "Kids").inOrder()
        assertThat(ordered).doesNotContain("[B] Kids")
    }
}

class StalkerDpadIndexTest {

    @Test
    fun iptvRowMaxActionIsAlwaysFive() {
        // Both M3U playlist rows and Stalker portal rows carry the same full
        // chip row (categories / toggle / edit / up / down / delete).
        assertThat(iptvRowMaxAction()).isEqualTo(5)
    }

    @Test
    fun firstIptvGroupIndexStartsAtOneForM3UPlaylists() {
        assertThat(
            firstIptvGroupIndex("list_1", listOf("Movies", "Kids"))
        ).isEqualTo(1)
    }

    @Test
    fun firstIptvGroupIndexStartsAtTwoForStalkerPortals() {
        // Each Stalker portal gets a bulk-toggle row at index 1.
        assertThat(
            firstIptvGroupIndex("stalker1", listOf("Movies", "Kids"), setOf("stalker1", "stalker2"))
        ).isEqualTo(2)
        assertThat(
            firstIptvGroupIndex("stalker2", listOf("News"), setOf("stalker1", "stalker2"))
        ).isEqualTo(2)
    }

    @Test
    fun firstIptvGroupIndexIsOneWhenGroupsEmptyEvenForStalker() {
        // No bulk-toggle row when there are no groups to toggle.
        assertThat(
            firstIptvGroupIndex("stalker1", emptyList(), setOf("stalker1"))
        ).isEqualTo(1)
    }

    @Test
    fun firstIptvGroupIndexIsOneForUnknownStalkerPlaylistId() {
        // Legacy STALKER_PLAYLIST_ID ("stalker") still gets bulk toggle.
        assertThat(
            firstIptvGroupIndex("stalker", listOf("Movies"), emptySet())
        ).isEqualTo(2)
    }
}
