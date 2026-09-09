package com.arflix.tv.ui.screens.tv.live

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.arflix.tv.data.repository.IptvPlaylistEntry
import com.arflix.tv.di.GuideAuditEntryPoint
import com.arflix.tv.di.RepositoryAccessEntryPoint
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in live-provider audit, isolated from both production and other emulator accounts. */
class GuideProviderAuditDeviceTest {
    @Test fun loadProvidedProviderAndKeepItsIndexAcrossCloudApplies() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val url = InstrumentationRegistry.getArguments().getString("playlistUrl")
        assumeTrue("Explicit audit URL required", !url.isNullOrBlank())
        check(context.packageName.endsWith(".iptvaudit") || context.packageName.endsWith(".overhaul"))
        val access = EntryPointAccessors.fromApplication(context, RepositoryAccessEntryPoint::class.java)
        val profiles = access.profileRepository()
        val profile = profiles.getProfiles().firstOrNull { it.name == "IPTV Provider Audit" }
            ?: profiles.createProfile("IPTV Provider Audit", 0xFF447777)
        profiles.setActiveProfile(profile.id)
        access.profileManager().setCurrentProfileId(profile.id)
        val repository = EntryPointAccessors.fromApplication(context, GuideAuditEntryPoint::class.java).iptvRepository()
        repository.savePlaylists(listOf(IptvPlaylistEntry("provider-audit", "Provider audit", url!!,
            importVod = false, importSeries = false)))
        val start = SystemClock.elapsedRealtime()
        var firstChannelsAt = 0L
        val snapshot = withTimeout(180_000) {
            repository.loadSnapshot(forcePlaylistReload = true, allowNetworkEpgFetch = false,
                onChannelsReady = { channels ->
                    if (channels.isNotEmpty() && firstChannelsAt == 0L) firstChannelsAt = SystemClock.elapsedRealtime() - start
                })
        }
        val count = repository.pagedChannelCount(null)
        val groups = repository.pagedPlaylistGroupCounts()
        report("provider_load_ms=${SystemClock.elapsedRealtime() - start} first_channels_ms=$firstChannelsAt channels=$count groups=${groups.size} memory_rows=${snapshot.channels.size}")
        val minimum = InstrumentationRegistry.getArguments().getString("minimumChannels")?.toIntOrNull() ?: 50_000
        assertTrue("Expected channels from the supplied provider", count >= minimum)
        assertEquals(count, groups.sumOf { it.third })
        listOf(groups.first(), groups[groups.size / 2], groups.last()).forEach { group ->
            val page = repository.pagedChannelWindow(group.first, group.second, 0, 144)
            assertEquals(minOf(144, group.third), page.size)
        }
        val state = repository.exportCloudConfigForProfile(profile.id)
        repeat(10) { repository.importCloudConfigForProfile(profile.id, state) }
        assertEquals(count, repository.pagedChannelCount(null))
        val selectedGroup = groups.firstOrNull { it.second.contains("NETHERLAND", true) }
            ?: groups.firstOrNull { Regex("\\bNL\\b", RegexOption.IGNORE_CASE).containsMatchIn(it.second) }
            ?: groups.first()
        val selected = repository.pagedChannelWindow(selectedGroup.first, selectedGroup.second, 0, 144)
            .filter { !it.epgId.isNullOrBlank() }.take(2)
        repository.importCloudConfigForProfile(profile.id, state.copy(favoriteChannels = selected.map { it.id }))
        assertEquals(count, repository.pagedChannelCount(null))
        report("unchanged_sync_applies=10 preference_only_apply=1 retained_channels=$count")
        val epgAt = SystemClock.elapsedRealtime()
        val guide = withTimeout(60_000) {
            repository.refreshEpgForChannels(selected.map { it.id }.toSet(), maxChannels = 2)
        }.orEmpty()
        report("focused_epg_ms=${SystemClock.elapsedRealtime() - epgAt} requested=${selected.size} matched=${guide.size} group=${selectedGroup.second}")
        if (guide.isEmpty() || InstrumentationRegistry.getArguments().getString("fullXml") == "true") {
            val fullStart = SystemClock.elapsedRealtime()
            withTimeout(600_000) {
                repository.loadSnapshot(forceEpgReload = true, allowNetworkEpgFetch = true, allowBroadShortEpg = false)
            }
            val indexed = repository.reDeriveCachedNowNext(selected.map { it.id }.toSet()).orEmpty()
            report("full_xml_ms=${SystemClock.elapsedRealtime() - fullStart} indexed_channels=${repository.indexedGuideChannelCount()} indexed_programs=${repository.indexedGuideProgramCount()} requested_matches=${indexed.size}")
            assertTrue("Dutch guide must load through XMLTV when the short API is empty", indexed.isNotEmpty())
            assertTrue("Only a completed full pass may mark the full guide fresh", repository.completedFullGuideAgeMs() < 60_000)
        }
    }

    @Test fun reopenProviderCacheWithoutDownloadingTheListsAgain() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("cachedStartup") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.packageName.endsWith(".iptvaudit") || context.packageName.endsWith(".overhaul"))
        val repository = EntryPointAccessors.fromApplication(context, GuideAuditEntryPoint::class.java).iptvRepository()
        val start = SystemClock.elapsedRealtime()
        repository.warmupFromCacheOnly()
        val count = repository.pagedChannelCount(null)
        val groups = repository.pagedPlaylistGroupCounts()
        val channelAt = SystemClock.elapsedRealtime() - start
        val selectedGroup = groups.firstOrNull { it.second.contains("NETHERLAND", true) } ?: groups.first()
        val selected = repository.pagedChannelWindow(selectedGroup.first, selectedGroup.second, 0, 144)
            .filter { !it.epgId.isNullOrBlank() }.take(2)
        val guide = repository.reDeriveCachedNowNext(selected.map { it.id }.toSet()).orEmpty()
        report("cached_channels_ms=$channelAt cached_channels_and_epg_ms=${SystemClock.elapsedRealtime() - start} channels=$count groups=${groups.size} matched=${guide.size}")
        val minimum = InstrumentationRegistry.getArguments().getString("minimumChannels")?.toIntOrNull() ?: 50_000
        assertTrue(count >= minimum)
        assertEquals(2, guide.size)
        assertTrue("Cached startup must not repeat the lengthy import", SystemClock.elapsedRealtime() - start < 5_000)
    }

    private fun report(message: String) {
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putString("stream", "$message\n") })
    }
}
