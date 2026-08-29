package com.arflix.tv.data.repository

import com.arflix.tv.data.api.StalkerApi
import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvProgram
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the Stalker EPG merge helpers on [IptvRepository] (marked `internal`
 * so tests can call them directly, same convention as [IptvEpgIndex]/[StalkerPortalSupport]).
 * Isolation comes from the channel id prefix (see [StalkerPortalSupport]), not a
 * separate per-portal EPG-index source key.
 */
class IptvRepositoryStalkerEpgTest {

    private fun newRepository(): IptvRepository {
        val context = io.mockk.mockk<android.content.Context>(relaxed = true)
        val okHttpClient = io.mockk.mockk<okhttp3.OkHttpClient>(relaxed = true)
        val profileManager = io.mockk.mockk<ProfileManager>(relaxed = true)
        val invalidationBus = io.mockk.mockk<CloudSyncInvalidationBus>(relaxed = true)
        return IptvRepository(context, okHttpClient, profileManager, invalidationBus)
    }

    private fun stubStalkerApi(respond: (String) -> String?): StalkerApi =
        object : StalkerApi("http://portal.example.com", "00:1A:79:AA:BB:CC") {
            override fun doGet(url: String): String = respond(url) ?: error("Unexpected url: $url")
        }

    private fun program(startMs: Long, endMs: Long, title: String) =
        IptvProgram(title = title, startUtcMillis = startMs, endUtcMillis = endMs)

    @Test
    fun `stalkerNowNextFromPrograms returns null for empty list`() {
        val repository = newRepository()
        assertNull(repository.stalkerNowNextFromPrograms(emptyList(), nowMs = 10_000L))
    }

    @Test
    fun `stalkerNowNextFromPrograms compacts sorted programs into now next later upcoming`() {
        val repository = newRepository()
        val nowMs = 10_000L
        val programs = listOf(
            program(0L, 5_000L, "Past"), // already over, not "now"
            program(5_000L, 15_000L, "Now"), // live at nowMs
            program(15_000L, 20_000L, "Next"),
            program(20_000L, 25_000L, "Later"),
            program(25_000L, 30_000L, "Upcoming1"),
            program(30_000L, 35_000L, "Upcoming2")
        )

        val result = repository.stalkerNowNextFromPrograms(programs.shuffled(), nowMs)

        requireNotNull(result)
        assertEquals("Now", result.now?.title)
        assertEquals("Next", result.next?.title)
        assertEquals("Later", result.later?.title)
        assertEquals(listOf("Upcoming1", "Upcoming2"), result.upcoming.map { it.title })
        assertTrue("Stalker EPG keeps no recent/catchup history (K10 out of scope)", result.recent.isEmpty())
    }

    @Test
    fun `fetchStalkerEpgForActivePortals keys results by full channel id and isolates portals`() = runTest {
        val repository = newRepository()
        val portal1Api = stubStalkerApi { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [
                    { "ch_id": "100", "name": "Portal1 News", "start_timestamp": "0", "stop_timestamp": "10" }
                ] }"""
            } else null
        }
        val portal2Api = stubStalkerApi { url ->
            if (url.contains("action=get_simple_data_table")) {
                // Same ch_id as portal 1 on purpose: without isolation this would collide (C1/C6).
                """{ "js": [
                    { "ch_id": "100", "name": "Portal2 Movie", "start_timestamp": "0", "stop_timestamp": "10" }
                ] }"""
            } else null
        }
        val channels = listOf(
            IptvChannel(id = "stalker:stalker1:100", name = "Ch A", logo = null, group = "g", streamUrl = "cmd"),
            IptvChannel(id = "stalker:stalker2:100", name = "Ch B", logo = null, group = "g", streamUrl = "cmd")
        )

        val result = repository.fetchStalkerEpgForActivePortals(
            mapOf("stalker1" to portal1Api, "stalker2" to portal2Api),
            channels
        )

        assertEquals(setOf("stalker:stalker1:100", "stalker:stalker2:100"), result.keys)
        assertEquals("Portal1 News", result.getValue("stalker:stalker1:100").now?.title)
        assertEquals("Portal2 Movie", result.getValue("stalker:stalker2:100").now?.title)
    }

    @Test
    fun `fetchStalkerEpgForActivePortals skips programs with unknown channel id or malformed timestamps`() = runTest {
        val repository = newRepository()
        val api = stubStalkerApi { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [
                    { "ch_id": "999", "name": "Unknown channel", "start_timestamp": "0", "stop_timestamp": "10" },
                    { "ch_id": "100", "name": "Bad timestamps", "start_timestamp": "not-a-number", "stop_timestamp": "10" },
                    { "ch_id": "100", "name": "End before start", "start_timestamp": "10", "stop_timestamp": "5" }
                ] }"""
            } else null
        }
        val channels = listOf(
            IptvChannel(id = "stalker:stalker1:100", name = "Ch A", logo = null, group = "g", streamUrl = "cmd")
        )

        val result = repository.fetchStalkerEpgForActivePortals(mapOf("stalker1" to api), channels)

        assertTrue("No valid programs in the response, result must stay empty", result.isEmpty())
    }

    @Test
    fun `fetchStalkerEpgForActivePortals returns empty map without network calls when no portals or channels`() = runTest {
        val repository = newRepository()
        assertTrue(repository.fetchStalkerEpgForActivePortals(emptyMap(), emptyList()).isEmpty())
    }
}
