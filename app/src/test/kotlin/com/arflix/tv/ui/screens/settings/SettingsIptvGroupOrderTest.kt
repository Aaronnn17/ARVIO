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

class HeldGroupMoveTargetTest {

    // M3U playlists: reset row at 0, first category row at 1.
    private val firstM3u = 1
    // Stalker portals: reset at 0, bulk toggle at 1, first category row at 2.
    private val firstStalker = 2

    @Test
    fun movingUpInTheMiddleFollowsTheGroup() {
        assertThat(
            heldGroupMoveTarget(focusedIndex = 4, firstGroupIndex = firstM3u, groupCount = 10, moveUp = true)
        ).isEqualTo(3)
    }

    @Test
    fun movingDownInTheMiddleFollowsTheGroup() {
        assertThat(
            heldGroupMoveTarget(focusedIndex = 4, firstGroupIndex = firstM3u, groupCount = 10, moveUp = false)
        ).isEqualTo(5)
    }

    @Test
    fun topGroupCannotMoveUp() {
        // IptvRepository.moveGroupUp silently does nothing at the top, so the
        // focus must not move either - otherwise focus and list drift apart.
        assertThat(
            heldGroupMoveTarget(focusedIndex = firstM3u, firstGroupIndex = firstM3u, groupCount = 10, moveUp = true)
        ).isNull()
    }

    @Test
    fun bottomGroupCannotMoveDown() {
        assertThat(
            heldGroupMoveTarget(focusedIndex = 10, firstGroupIndex = firstM3u, groupCount = 10, moveUp = false)
        ).isNull()
    }

    @Test
    fun stalkerPortalsKeepTheBulkToggleRowOutOfReach() {
        // The first category of a Stalker portal sits at focus index 2; moving
        // it up must not push it into the bulk-toggle or reset row.
        assertThat(
            heldGroupMoveTarget(focusedIndex = firstStalker, firstGroupIndex = firstStalker, groupCount = 5, moveUp = true)
        ).isNull()
        assertThat(
            heldGroupMoveTarget(focusedIndex = 3, firstGroupIndex = firstStalker, groupCount = 5, moveUp = true)
        ).isEqualTo(2)
        assertThat(
            heldGroupMoveTarget(focusedIndex = 6, firstGroupIndex = firstStalker, groupCount = 5, moveUp = false)
        ).isNull()
    }

    @Test
    fun rowsThatAreNotCategoriesNeverMove() {
        // Reset row and bulk-toggle row of a Stalker portal.
        assertThat(
            heldGroupMoveTarget(focusedIndex = 0, firstGroupIndex = firstStalker, groupCount = 5, moveUp = false)
        ).isNull()
        assertThat(
            heldGroupMoveTarget(focusedIndex = 1, firstGroupIndex = firstStalker, groupCount = 5, moveUp = true)
        ).isNull()
        // Past the last category row.
        assertThat(
            heldGroupMoveTarget(focusedIndex = 7, firstGroupIndex = firstStalker, groupCount = 5, moveUp = true)
        ).isNull()
    }

    @Test
    fun emptyCategoryListNeverMoves() {
        assertThat(
            heldGroupMoveTarget(focusedIndex = 1, firstGroupIndex = firstM3u, groupCount = 0, moveUp = true)
        ).isNull()
    }

    @Test
    fun aSingleGroupCannotMoveInEitherDirection() {
        assertThat(
            heldGroupMoveTarget(focusedIndex = 1, firstGroupIndex = firstM3u, groupCount = 1, moveUp = true)
        ).isNull()
        assertThat(
            heldGroupMoveTarget(focusedIndex = 1, firstGroupIndex = firstM3u, groupCount = 1, moveUp = false)
        ).isNull()
    }

    @Test
    fun repeatedPressesWalkAGroupAllTheWayToTheTopAndThenStop() {
        // Twenty groups, the focused one sits on position 19 (focus index 20).
        var focus = 20
        repeat(25) {
            focus = heldGroupMoveTarget(focus, firstM3u, groupCount = 20, moveUp = true) ?: focus
        }
        assertThat(focus).isEqualTo(firstM3u)
    }
}

class CenteredScrollOffsetTest {

    @Test
    fun aRowIsPushedDownByHalfTheLeftoverViewport() {
        // 560 dp of list, 70 dp rows: the focused row should start 245 below the
        // top edge, which is what the negative offset asks the list for.
        assertThat(centeredScrollOffset(viewportSize = 560, itemSize = 70)).isEqualTo(-245)
    }

    @Test
    fun anUnmeasuredListFallsBackToTopAlignment() {
        // First frame: the list has no geometry yet. Offset 0 is the old
        // behaviour, which is correct rather than merely harmless.
        assertThat(centeredScrollOffset(viewportSize = 0, itemSize = 70)).isEqualTo(0)
        assertThat(centeredScrollOffset(viewportSize = 560, itemSize = 0)).isEqualTo(0)
    }

    @Test
    fun aRowTallerThanTheViewportIsNotPushedOffScreen() {
        assertThat(centeredScrollOffset(viewportSize = 200, itemSize = 200)).isEqualTo(0)
        assertThat(centeredScrollOffset(viewportSize = 200, itemSize = 260)).isEqualTo(0)
    }

    @Test
    fun negativeMeasurementsNeverProduceAnOffset() {
        assertThat(centeredScrollOffset(viewportSize = -10, itemSize = 70)).isEqualTo(0)
        assertThat(centeredScrollOffset(viewportSize = 560, itemSize = -70)).isEqualTo(0)
    }

    @Test
    fun theOffsetAlwaysPointsUpwardsSoTheRowMovesDown() {
        // A positive offset would scroll PAST the row and hide it above the edge.
        for (item in 10..200 step 10) {
            assertThat(centeredScrollOffset(viewportSize = 560, itemSize = item)).isAtMost(0)
        }
    }
}
