package com.arflix.tv.data.model

import com.arflix.tv.data.api.StremioMetaPreview
import java.net.URI
import java.text.Normalizer
import java.util.Locale

/** Artwork only. Addon status/times never overwrite the user's channel schedule. */
data class SportsEventArtwork(val title: String, val background: String, val genres: List<String>) {
    val key: String = sportsArtworkKey(title)
}

fun sportsArtworkKey(title: String): String = Normalizer.normalize(title, Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
    .replace(Regex("^(live\\s*[:|-]\\s*|live\\s+)"), "")
    .replace(Regex("^(football|soccer|basketball|baseball|tennis|ice hockey|american football|boxing|mma|cricket)\\s*:\\s*"), "")
    .replace(Regex("\\b(vs\\.?|versus|v\\.)\\s+"), "vs ")
    .replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()

fun StremioMetaPreview.toSportsEventArtwork(): SportsEventArtwork? {
    val title = name?.takeIf { it.isNotBlank() } ?: return null
    if (id?.startsWith("leaf:") == true) return null // Channel-recording covers are not match artwork.
    // Posters may contain UTC times. Backgrounds are the addon's untimed landscape assets.
    val image = background?.takeIf { it.isNotBlank() && !it.contains("_UTC", ignoreCase = true) } ?: return null
    val uri = runCatching { URI(image) }.getOrNull() ?: return null
    if (uri.scheme?.lowercase(Locale.ROOT) !in setOf("https", "http") || uri.host.isNullOrBlank()) return null
    return SportsEventArtwork(title, image, genres.orEmpty())
}
