package com.arflix.tv.testing

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.arflix.tv.util.settingsDataStore
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.rules.ExternalResource
import java.io.File
import java.nio.file.Files

/** Prevent the process-wide delegate from retaining another Robolectric test's deleted directory. */
class IsolatedSettingsStoreRule : ExternalResource() {
    private val job = SupervisorJob()
    private lateinit var directory: File

    override fun before() {
        directory = Files.createTempDirectory("arvio-test-settings-").toFile()
        val store = PreferenceDataStoreFactory.create(
            scope = CoroutineScope(job + Dispatchers.IO),
            produceFile = { File(directory, "settings.preferences_pb") }
        )
        mockkStatic("com.arflix.tv.util.DataStoresKt")
        every { any<Context>().settingsDataStore } returns store
    }

    override fun after() {
        try {
            runBlocking { job.cancelAndJoin() }
        } finally {
            unmockkStatic("com.arflix.tv.util.DataStoresKt")
            directory.deleteRecursively()
        }
    }
}
