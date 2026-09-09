package com.arflix.tv.data.repository

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.arflix.tv.data.model.IptvChannel
import com.arflix.tv.data.model.IptvGuideHistory
import com.arflix.tv.data.model.IptvNowNext
import com.arflix.tv.data.model.IptvProgram
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class IptvStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun fiftyThousandChannelsSurviveReloadAndEveryGroupPagesInProviderOrder() {
        val key = "device-regression-${UUID.randomUUID()}"
        var store = IptvChannelStore(context)
        try {
            val all = listOf("first", "second").flatMap { provider ->
                (0 until 5).flatMap { group -> List(5_000) { index ->
                    IptvChannel("$provider:$group:$index", "Channel $index",
                        "https://example.invalid/$index.ts", "Group $group")
                } }
            }
            store.replaceAll(key, all, System.currentTimeMillis())
            store.close()
            store = IptvChannelStore(context)
            val startupAt = SystemClock.elapsedRealtime()
            assertEquals(240, store.loadStartupChannels(key, 10_000, 240).size)
            assertEquals(50_000, store.count(key))
            val labels = mutableListOf<String>()
            store.visitLabels(key, "second") { id, _, _ -> labels.add(id) }
            assertEquals(all.filter { it.id.startsWith("second:") }.map { it.id }, labels)
            Log.i("IptvStoreDeviceTest", "50k cold store startupMs=${SystemClock.elapsedRealtime() - startupAt}")
            val startedAt = SystemClock.elapsedRealtime()
            listOf("first", "second").forEach { provider -> (0 until 5).forEach { group ->
                assertEquals(5_000, store.countForPlaylistGroup(key, provider, "Group $group"))
                assertEquals(-1, store.indexOfId(key, provider, "Group $group", "other-provider:4:4999"))
                val actual = (0 until 5_000 step 144).flatMap { offset ->
                    store.windowForPlaylistGroup(key, provider, "Group $group", offset, 144).map { it.id }
                }
                assertEquals(List(5_000) { "$provider:$group:$it" }, actual)
            } }
            Log.i("IptvStoreDeviceTest", "50k paged rows verified groups=10 providers=2 totalReadMs=${SystemClock.elapsedRealtime() - startedAt}")
        } finally {
            store.deleteSource(key)
            store.close()
        }
    }

    @Test
    fun fullArchiveSurvivesShortGuideRefreshAndProcessStyleDatabaseReopen() {
        val key = "device-regression-${UUID.randomUUID()}"
        val channelId = "second:1"
        val now = System.currentTimeMillis()
        val interval = 15 * 60_000L
        val history = List(288) { i -> IptvProgram("Archive $i",
            startUtcMillis = now - (288 - i) * interval, endUtcMillis = now - (287 - i) * interval) }
        var store = IptvEpgIndex(context)
        try {
            store.replaceChannels(key, mapOf(channelId to IptvNowNext(recent = history)), now)
            store.close()
            store = IptvEpgIndex(context)
            store.replaceChannels(key, mapOf(channelId to IptvNowNext(now = IptvProgram("Live",
                startUtcMillis = now, endUtcMillis = now + interval))), now)
            store.replaceAll(key, mapOf(channelId to IptvNowNext(now = IptvProgram("Live",
                startUtcMillis = now, endUtcMillis = now + interval))), now)
            val startedAt = SystemClock.elapsedRealtime()
            val guide = store.loadNowNext(key, setOf(channelId), now,
                pastWindowMs = IptvGuideHistory.MAX_WINDOW_MS, recentProgramLimit = IptvGuideHistory.MAX_PROGRAMS)
                .getValue(channelId)
            assertEquals(history, guide.recent)
            assertEquals("Live", guide.now?.title)
            Log.i("IptvStoreDeviceTest", "72h archive records=288 readMs=${SystemClock.elapsedRealtime() - startedAt}")
        } finally {
            store.deleteSource(key)
            store.close()
        }
    }
}
