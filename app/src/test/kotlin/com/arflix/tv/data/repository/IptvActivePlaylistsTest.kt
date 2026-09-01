package com.arflix.tv.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regression tests for [IptvRepository.activePlaylists] (marked `internal` so tests can
 * call it directly, same convention as the Stalker EPG helpers).
 *
 * Root cause: `observeConfig()` always mirrors `playlists.firstOrNull()?.m3uUrl` into the
 * legacy top-level `config.m3uUrl` field, regardless of that entry's `enabled` state - it's
 * kept in sync for backward compatibility, not cleared on migration. `activePlaylists()`
 * used to treat "zero enabled playlists" as "never migrated" and resurrect a synthetic,
 * always-enabled "List 1" entry from that legacy field - so disabling the only configured
 * M3U playlist did nothing: the disabled entry's own URL came right back via the legacy
 * fallback, under a name ("List 1") that isn't the one the user configured.
 */
class IptvActivePlaylistsTest {

    private fun newRepository(): IptvRepository {
        val context = io.mockk.mockk<android.content.Context>(relaxed = true)
        val okHttpClient = io.mockk.mockk<okhttp3.OkHttpClient>(relaxed = true)
        val profileManager = io.mockk.mockk<ProfileManager>(relaxed = true)
        val invalidationBus = io.mockk.mockk<CloudSyncInvalidationBus>(relaxed = true)
        return IptvRepository(context, okHttpClient, profileManager, invalidationBus)
    }

    @Test
    fun `enabled playlists are returned as configured`() {
        val repository = newRepository()
        val playlist = IptvPlaylistEntry(
            id = "my_list",
            name = "My Provider",
            m3uUrl = "http://example.com/list.m3u",
            enabled = true
        )
        val config = IptvConfig(
            m3uUrl = playlist.m3uUrl,
            playlists = listOf(playlist)
        )

        assertEquals(listOf(playlist), repository.activePlaylists(config))
    }

    @Test
    fun `disabling the only configured playlist does not resurrect it via the legacy m3uUrl field`() {
        val repository = newRepository()
        // config.m3uUrl mirrors the (disabled) entry's URL, as observeConfig() always does -
        // this must NOT bring the playlist back to life.
        val disabled = IptvPlaylistEntry(
            id = "my_list",
            name = "My Provider",
            m3uUrl = "http://example.com/list.m3u",
            enabled = false
        )
        val config = IptvConfig(
            m3uUrl = disabled.m3uUrl,
            playlists = listOf(disabled)
        )

        assertTrue(repository.activePlaylists(config).isEmpty())
        assertTrue(repository.hasAnyConfiguredSource(config).not())
    }

    @Test
    fun `disabling one of several playlists keeps the rest active`() {
        val repository = newRepository()
        val enabled = IptvPlaylistEntry(
            id = "list_a",
            name = "Provider A",
            m3uUrl = "http://example.com/a.m3u",
            enabled = true
        )
        val disabled = IptvPlaylistEntry(
            id = "list_b",
            name = "Provider B",
            m3uUrl = "http://example.com/b.m3u",
            enabled = false
        )
        val config = IptvConfig(
            m3uUrl = enabled.m3uUrl,
            playlists = listOf(enabled, disabled)
        )

        assertEquals(listOf(enabled), repository.activePlaylists(config))
    }

    @Test
    fun `legacy pre-migration config with no playlist entries still falls back to m3uUrl`() {
        val repository = newRepository()
        val config = IptvConfig(
            m3uUrl = "http://example.com/legacy.m3u",
            playlists = emptyList()
        )

        val result = repository.activePlaylists(config)

        assertEquals(1, result.size)
        assertEquals("http://example.com/legacy.m3u", result.single().m3uUrl)
        assertTrue(result.single().enabled)
        assertTrue(repository.hasAnyConfiguredSource(config))
    }

    @Test
    fun `no playlists and no legacy m3uUrl returns nothing`() {
        val repository = newRepository()
        val config = IptvConfig(playlists = emptyList(), m3uUrl = "")

        assertTrue(repository.activePlaylists(config).isEmpty())
    }
}
