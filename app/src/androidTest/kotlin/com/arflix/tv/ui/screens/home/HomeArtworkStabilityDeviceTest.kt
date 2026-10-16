package com.arflix.tv.ui.screens.home

import android.graphics.drawable.ColorDrawable
import androidx.activity.ComponentActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import coil.ImageLoader
import coil.decode.DataSource
import coil.fetch.DrawableResult
import coil.fetch.Fetcher
import coil.request.Options
import com.arflix.tv.data.model.MediaItem
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean

class HomeArtworkStabilityDeviceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val gate = CompletableDeferred<Unit>()
    private var loader: ImageLoader? = null
    @After fun close() { gate.complete(Unit); loader?.shutdown() }

    @Test fun expandingPosterKeepsItsImageUntilTheBackdropIsReady() {
        val requested = AtomicBoolean(false)
        val factory = object : Fetcher.Factory<android.net.Uri> {
            override fun create(data: android.net.Uri, options: Options, imageLoader: ImageLoader): Fetcher? {
                if (data.scheme != "fixture") return null
                val backdrop = data.toString().endsWith("backdrop")
                return Fetcher {
                    if (backdrop) { requested.set(true); gate.await() }
                    DrawableResult(ColorDrawable(if (backdrop) android.graphics.Color.BLUE else android.graphics.Color.RED),
                        false, DataSource.NETWORK)
                }
            }
        }
        val images = ImageLoader.Builder(compose.activity).components { add(factory) }.build().also { loader = it }
        val expanded = mutableStateOf(false)
        val title = MediaItem(1, "Fixture", image = "fixture:poster", backdrop = "fixture:backdrop")
        compose.setContent {
            Image(rememberNetflixArtwork(title, expanded.value, 120.dp, 90.dp, false, images), null,
                modifier = Modifier.size(120.dp, 90.dp).testTag("stable-artwork"))
        }
        compose.waitUntil(5_000) { center() == Color.Red }
        compose.runOnIdle { expanded.value = true }
        compose.waitUntil(5_000) { requested.get() }
        repeat(5) {
            assertEquals("A pending focus image must not blank the existing artwork", Color.Red, center())
        }
        gate.complete(Unit)
        compose.waitUntil(5_000) { center() == Color.Blue }
    }

    private fun center(): Color {
        val pixels = compose.onNodeWithTag("stable-artwork").captureToImage().toPixelMap()
        return pixels[pixels.width / 2, pixels.height / 2]
    }
}
