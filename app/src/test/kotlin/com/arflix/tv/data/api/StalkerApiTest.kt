package com.arflix.tv.data.api

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private const val PORTAL = "http://portal.example.com"
private const val MAC = "00:1A:79:AA:BB:CC"

class StalkerApiTest {

    private fun stubApi(
        portal: String = PORTAL,
        requests: MutableList<String>,
        respond: (String) -> String?
    ): StalkerApi =
        object : StalkerApi(portal, MAC) {
            override fun doGet(url: String): String {
                requests += url
                return respond(url) ?: error("Unexpected url: $url")
            }
        }

    @Test
    fun `handshake stops probing once root returns JSON token`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=handshake") -> """{ "js": { "token": "ABC123" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertEquals(
            listOf(
                "$PORTAL/server/load.php?type=stb&action=handshake",
                "$PORTAL/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `handshake skips HTML responses and falls through to stalker_portal`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url == "$PORTAL/server/load.php?type=stb&action=handshake" -> "<html>404</html>"
                url.contains("/stalker_portal/server/load.php?type=stb&action=handshake") ->
                    """{ "js": { "token": "T" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertEquals(
            listOf(
                "$PORTAL/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `handshake fails when no token is present`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            if (url.contains("action=handshake")) """{ "js": {} }""" else null
        }

        val ok = api.handshake()

        assertFalse(ok)
        assertTrue("all requests must be handshake probes", requests.all { it.contains("action=handshake") })
    }

    @Test
    fun `handshake resolves API at root when portal URL ends with slash c`() = runTest {
        val requests = mutableListOf<String>()
        // Typical /c/ portals answer the handshake with an HTML 404 page under /c/,
        // the real API lives at the root.
        val api = stubApi(portal = "$PORTAL/c", requests = requests) { url ->
            when {
                url == "$PORTAL/c/server/load.php?type=stb&action=handshake" ->
                    "<!DOCTYPE html><html><body>404 Not Found</body></html>"
                url == "$PORTAL/server/load.php?type=stb&action=handshake" ->
                    """{ "js": { "token": "ROOT" } }"""
                url.contains("action=handshake&token=") -> """{ "js": { "token": "ROOT" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertEquals(
            listOf(
                "$PORTAL/c/server/load.php?type=stb&action=handshake",
                "$PORTAL/server/load.php?type=stb&action=handshake",
                "$PORTAL/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `handshake skips empty responses for slash c portal and falls through to stalker_portal`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(portal = "$PORTAL/c", requests = requests) { url ->
            when {
                url == "$PORTAL/c/server/load.php?type=stb&action=handshake" -> ""
                url == "$PORTAL/server/load.php?type=stb&action=handshake" -> "<html>404</html>"
                url == "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake" ->
                    """{ "js": { "token": "SP" } }"""
                url.contains("action=handshake&token=") -> """{ "js": { "token": "SP" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertEquals(
            listOf(
                "$PORTAL/c/server/load.php?type=stb&action=handshake",
                "$PORTAL/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `handshake resolves API for slash stalker_portal slash c portal URL`() = runTest {
        val requests = mutableListOf<String>()
        // /stalker_portal/c/ style URL: the UI path must be stripped to /stalker_portal.
        val api = stubApi(portal = "$PORTAL/stalker_portal/c", requests = requests) { url ->
            when {
                url == "$PORTAL/stalker_portal/c/server/load.php?type=stb&action=handshake" ->
                    "<!DOCTYPE html><html><body>404 Not Found</body></html>"
                url == "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake" ->
                    """{ "js": { "token": "SPC" } }"""
                url.contains("action=handshake&token=") -> """{ "js": { "token": "SPC" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertEquals(
            listOf(
                "$PORTAL/stalker_portal/c/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake",
                "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `handshake does not stop probing on HTML 404 without token`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url == "$PORTAL/server/load.php?type=stb&action=handshake" ->
                    "<!DOCTYPE html><html><body>404 Not Found</body></html>"
                url == "$PORTAL/stalker_portal/server/load.php?type=stb&action=handshake" ->
                    """{ "js": { "token": "LATE" } }"""
                url.contains("action=handshake&token=") -> """{ "js": { "token": "LATE" } }"""
                else -> null
            }
        }

        val ok = api.handshake()

        assertTrue(ok)
        assertTrue(requests.any { it.contains("/stalker_portal/") })
    }

    @Test
    fun `channel pagination stops and deduplicates when a portal repeats the first page`() = runTest {
        val requests = mutableListOf<String>()
        val repeatedPage = """{
            "js": {
                "data": [
                    { "id": 1, "name": "One", "cmd": "ffmpeg http://one", "tv_genre_id": "1" },
                    { "id": 2, "name": "Two", "cmd": "ffmpeg http://two", "tv_genre_id": "1" }
                ],
                "total_items": 6,
                "max_page_items": 2
            }
        }"""
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=get_genres") ->
                    """{ "js": [{ "id": "1", "title": "News" }] }"""
                url.contains("action=get_all_channels") -> repeatedPage
                else -> null
            }
        }

        val channels = api.getChannels()

        assertEquals(listOf("1", "2"), channels.map { it.id })
        assertEquals(2, requests.count { it.contains("action=get_all_channels") })
        assertFalse(requests.any { it.contains("p=3") })
    }

    @Test
    fun `getEpg builds url without date param when date is blank`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [{ "ch_id": "1", "name": "News", "start_timestamp": "1000", "stop_timestamp": "2000" }] }"""
            } else null
        }

        api.getEpg()

        // get_simple_data_table returned data, so no fallback request is made.
        assertEquals(
            listOf("$PORTAL/server/load.php?type=epg&action=get_simple_data_table&ch_id=all&JsHttpRequest=1-xml"),
            requests
        )
    }

    @Test
    fun `getEpg appends encoded date param when date is set`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [{ "ch_id": "1", "name": "News", "start_timestamp": "1000", "stop_timestamp": "2000" }] }"""
            } else null
        }

        api.getEpg(date = "2026-08-29")

        assertEquals(
            listOf(
                "$PORTAL/server/load.php?type=epg&action=get_simple_data_table&ch_id=all&date=2026-08-29&JsHttpRequest=1-xml"
            ),
            requests
        )
    }

    @Test
    fun `getEpg parses standard field names`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [
                    { "ch_id": "1", "name": "News", "descr": "Daily news", "start_timestamp": "1000", "stop_timestamp": "2000" }
                ] }"""
            } else null
        }

        val programs = api.getEpg()

        assertEquals(1, programs.size)
        assertEquals("1", programs[0].chId)
        assertEquals("News", programs[0].name)
        assertEquals("Daily news", programs[0].descr)
        assertEquals("1000", programs[0].startTimestamp)
        assertEquals("2000", programs[0].stopTimestamp)
    }

    @Test
    fun `getEpg parses alternate field names from other portal software`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            if (url.contains("action=get_simple_data_table")) {
                """{ "js": [
                    { "channel_id": "7", "title": "Movie", "description": "A film", "start": "1500", "end": "3000" }
                ] }"""
            } else null
        }

        val programs = api.getEpg()

        assertEquals(1, programs.size)
        assertEquals("7", programs[0].chId)
        assertEquals("Movie", programs[0].name)
        assertEquals("A film", programs[0].descr)
        assertEquals("1500", programs[0].startTimestamp)
        assertEquals("3000", programs[0].stopTimestamp)
    }

    @Test
    fun `getEpg falls back to get_epg_info when get_simple_data_table is malformed`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=get_simple_data_table") -> "<html>not json</html>"
                url.contains("action=get_epg_info") -> """{ "js": [] }"""
                else -> null
            }
        }

        val programs = api.getEpg()

        assertTrue(programs.isEmpty())
        assertEquals(2, requests.size)
        assertTrue(requests[0].contains("action=get_simple_data_table"))
        assertTrue(requests[1].contains("action=get_epg_info"))
    }

    @Test
    fun `getEpg falls back to get_epg_info when js is null or absent`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=get_simple_data_table") -> """{ "js": null }"""
                url.contains("action=get_epg_info") -> """{ "js": null }"""
                else -> null
            }
        }

        val programs = api.getEpg()

        assertTrue(programs.isEmpty())
        assertEquals(2, requests.size)
    }

    @Test
    fun `getEpg get_epg_info fallback parses a flat js list like get_simple_data_table`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=get_simple_data_table") -> """{ "js": [] }"""
                url.contains("action=get_epg_info") ->
                    """{ "js": [{ "ch_id": "1", "name": "News", "start_timestamp": "1000", "stop_timestamp": "2000" }] }"""
                else -> null
            }
        }

        val programs = api.getEpg()

        assertEquals(1, programs.size)
        assertEquals("1", programs[0].chId)
        assertEquals("News", programs[0].name)
    }

    @Test
    fun `getEpg get_epg_info fallback parses a per-channel object shape`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests = requests) { url ->
            when {
                url.contains("action=get_simple_data_table") -> """{ "js": [] }"""
                url.contains("action=get_epg_info") ->
                    """{ "js": {
                        "1": [{ "name": "News", "start_timestamp": "1000", "stop_timestamp": "2000" }],
                        "2": [{ "name": "Movie", "start_timestamp": "1500", "stop_timestamp": "3000" }]
                    } }"""
                else -> null
            }
        }

        val programs = api.getEpg()

        assertEquals(2, programs.size)
        // The per-channel object's key becomes ch_id since the program entry itself has none.
        assertEquals(setOf("1", "2"), programs.map { it.chId }.toSet())
        assertEquals(setOf("News", "Movie"), programs.map { it.name }.toSet())
    }
}
