package com.arflix.tv.data.api

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private const val PORTAL = "http://portal.example.com"
private const val MAC = "00:1A:79:AA:BB:CC"

class StalkerApiTest {

    private fun stubApi(requests: MutableList<String>, respond: (String) -> String?): StalkerApi =
        object : StalkerApi(PORTAL, MAC) {
            override fun doGet(url: String): String {
                requests += url
                return respond(url) ?: error("Unexpected url: $url")
            }
        }

    @Test
    fun `handshake stops probing once root returns JSON token`() = runTest {
        val requests = mutableListOf<String>()
        val api = stubApi(requests) { url ->
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
        val api = stubApi(requests) { url ->
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
        val api = stubApi(requests) { url ->
            if (url.contains("action=handshake")) """{ "js": {} }""" else null
        }

        val ok = api.handshake()

        assertFalse(ok)
        assertTrue("all requests must be handshake probes", requests.all { it.contains("action=handshake") })
    }
}
