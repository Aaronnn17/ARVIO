# ARVIO iOS Parity Matrix

This matrix is the working contract for bringing the iPhone/iPad app to user-feature parity with the Android app on `origin/main`.

Status values:

- `Done`: implemented in iOS and has direct source evidence.
- `Partial`: source exists but misses Android behavior, UI, state, or verification.
- `Missing`: no iOS equivalent exists yet.
- `Android-only`: platform behavior that cannot be identical on iOS and needs an iOS-specific equivalent or explicit exclusion.
- `Unverified`: likely present, but not proven by build/runtime evidence yet.

## Scope Rule

iOS must match Android user features and visual language. Android-specific mechanics such as APK self-update installation, Android DataStore, Hilt, ExoPlayer/Media3 internals, DEX extension loading, Android TV DPAD focus internals, unknown-source settings, and launcher integration do not need literal iOS copies. They still need an honest iOS equivalent where the user-facing feature matters.

## Current Imported iOS Baseline

The iOS baseline has been imported from `origin/codex/ios-live-tv-profiles` into the clean parity worktree. It includes:

- SwiftUI app shell, Android-like left sidebar navigation, Movies/Series/Live TV/Search/Watchlist/Settings routes, ARVIO branding, and TestFlight workflow.
- Cloud auth/session, Android-style device-code cloud pairing, profile service, cloud sync service with latest-remote merge before saves.
- TMDB home/search/details, catalog service, catalog details.
- Trakt device auth, watchlist, progress/scrobble hooks.
- Watch history/continue watching.
- Addon install/toggle/remove and Stremio stream resolving.
- Plugins & Extensions repository/scraper management for Android-style metadata, Nuvio JS execution through JavaScriptCore, with external DEX execution explicitly classified as Android-only.
- Home server service for Jellyfin/Plex-style catalogs and sources.
- IPTV service and Live TV view.
- AVPlayer playback, sources panel, tracks panel, external subtitles, AI subtitle translation, skip intro, progress save, fallback source attempt.
- KMP `shared` module with title matching, stream ranking, Xtream paths, VOD matching, progress helpers, and M3U helpers.

## Feature Matrix

| Area | Android Source Evidence | iOS Source Evidence | Status | Required Work |
| --- | --- | --- | --- | --- |
| App shell and routes | `AppNavigation.kt` routes: login, home, movies, series, search, watchlist, tv, settings, telegram, profile selection, collection details, details, player | `RootView.swift`, `MediaBrowserView.swift`, sidebar tabs and selected overlays | Partial | iOS now has Home/Movies/Series/Live TV/Watchlist/Search/Settings plus details/player/catalog overlays. Telegram remains separate/missing. |
| Android TV visual language | `HomeScreen.kt`, `DetailsScreen.kt`, `SettingsScreen.kt`, `LiveTvScreen.kt`, `PlayerScreen.kt`, `ArvioSkin*` | `Theme.swift`, `RootView.swift`, `Components.swift`, screen views | Partial | Recheck iPad and iPhone layouts against Android screenshots; polish spacing, focus rings, density, empty/loading states. |
| Login and cloud account | `LoginScreen.kt`, `LoginViewModel.kt`, `AuthRepository.kt`, `TvDeviceAuthRepository.kt`, settings cloud auth | `AuthService.swift`, `SettingsView.swift`, `CloudSyncService.swift` | Partial | iOS has email/password auth and Android-compatible cloud device-code pairing. Needs real Supabase function test on device/TestFlight. |
| Profiles | `ProfileSelectionScreen.kt`, `ProfileDialogs.kt`, `PinEntryDialog.kt`, `ProfileViewModel.kt`, `ProfileRepository.kt` | `ProfileService.swift`, `ProfileSelectionView.swift` | Partial | Verify create/delete/switch/PIN/avatar parity and cloud sync shape. |
| Home hero and rails | `HomeScreen.kt`, `HomeViewModel.kt`, `CatalogRepository.kt`, `MediaRepository.kt`, `ContinueWatchingSelector.kt` | `HomeView.swift`, `CatalogService.swift`, `TmdbService.swift`, `WatchHistoryService.swift` | Partial | Verify row ordering, hero actions, context menu actions, loading skeletons, budget/spoiler/settings behavior. |
| Continue watching | `WatchHistoryRepository.kt`, `TraktRepository.kt`, `TraktSyncService.kt`, `ContinueWatchingCard.kt` | `WatchHistoryService.swift`, `HomeView.swift`, `PlayerView.swift` | Partial | Verify cloud + Trakt merge semantics and progress persistence with real account. |
| Movies/Series/Search | `SearchScreen.kt`, `SearchViewModel.kt`, `MediaRepository.kt`, Android top-level Movies/Series routes | `SearchView.swift`, `MediaBrowserView.swift`, `TmdbService.swift` | Partial | iOS now has dedicated Movies/Series discovery tabs, filtered search/discovery, person-known-for rows, Android-style search ranking, and smart queries such as top/best/new/similar-to searches. Needs screenshot/runtime comparison against Android. |
| Details page | `DetailsScreen.kt`, `DetailsViewModel.kt`, `StreamSelector.kt`, `PersonModal.kt`, trailers/cast/recommendations/episodes/reviews/collections | `DetailsView.swift`, `TmdbService.swift`, `TrailerPlayerView.swift` | Partial | iOS now includes play/resume, sources, watchlist, local/Trakt watched state, trailer, episodes, cast rail, TMDB-backed person modal, known-for navigation, collection/franchise rail, reviews, and recommendations. Needs iPad/iPhone runtime comparison against Android focus/mobile layouts and real source playback. |
| Source selector | `StreamSelector.kt`, `StreamRepository.kt`, `AddonRuntimeAggregator.kt`, quality filters | `SourceSelector` in `DetailsView.swift`, `StreamResolver.swift` | Partial | iOS now sorts with shared stream scoring, shows source stats, addon tabs, optional repository grouping, quality/size/playable/subtitle/provider badges, best-source highlighting, cached/debrid indicators, quality filters, provider labels, and autoplay minimum quality. Needs real addon/provider runtime comparison against Android's exact focus and loading-progress behavior. |
| Playback | `PlayerScreen.kt`, `PlayerViewModel.kt`, Media3/ExoPlayer, progress, next episode, controls | `PlayerView.swift`, AVPlayer, progress/scrobble, fallback, tracks, skip intro, next episode countdown, source retry, 10-second seek controls, scrubber, and fit/zoom/fill aspect cycling | Partial | Full real-device verification for stream formats, headers, redirects, progress, next episode countdown, seek/scrub controls, aspect modes, and error retry. |
| Remote playback | `CastManager.kt`, `CastOptionsProvider.kt`, `PlayerScreen.kt` Chromecast route button and remote controls | `PlayerView.swift` AVPlayer AirPlay route picker | Partial | iOS now exposes AirPlay routing for AVPlayer streams. Full Chromecast parity would require adding the Google Cast iOS SDK and real-device route/session testing. |
| Subtitles/audio tracks | `AudioTrackSelector.kt`, `SubtitleScoring.kt`, `SubtitleTranslationManager.kt`, subtitle settings | `PlayerView.swift`, `SubtitleTranslationService.swift`, `SettingsService.swift` | Partial | Verify default/secondary subtitles, filtering, styling, AI translation, remove-HI, offset/size/color/style behavior. |
| Skip intro | `SkipIntroRepository.kt`, `SkipIntroButton.kt`, `PlayerScreen.kt` | `SkipIntroService.swift`, `PlayerView.swift` | Partial | Verify IntroDB/AniSkip matching and button timing. |
| Watchlist | `WatchlistScreen.kt`, `WatchlistViewModel.kt`, `WatchlistRepository.kt`, `TraktRepository.kt` | `WatchlistView.swift`, `TraktService.swift` | Partial | Verify filters/search/hydration/open/remove/playable details parity. |
| Trakt | `TraktApi.kt`, `TraktRepository.kt`, `TraktSyncService.kt`, settings sync controls | `TraktService.swift`, `WatchHistoryService.swift` | Partial | Verify OAuth device flow, token refresh, watchlist add/remove, playback progress, mark watched, sync counts/time. |
| Catalogs | `CatalogRepository.kt`, `CatalogDiscoveryRepository.kt`, `CatalogModels.kt`, settings catalogs | `CatalogService.swift`, `CatalogDetailView`, `TmdbService.swift`, `SettingsView.swift` | Partial | iOS now supports profile catalog rows, direct custom URLs, Trakt/MDBList public list discovery, row ordering/layout/hide/delete. Needs real search/runtime verification. |
| Stremio addons | `StreamRepository.kt`, `AddonRuntime*`, `SettingsScreen.kt` Stremio section | `AddonService.swift`, `SettingsView.swift`, `StreamResolver.swift` | Partial | Stremio Addons now live under Settings like Android. Verify install URL normalization, profile/cloud sync, runtime behavior, and catalog sync with real addons. |
| Sideload plugin system | `PluginScreen.kt`, `PluginViewModel.kt`, `PluginManager.kt`, `PluginDataStore.kt`, `domain/model/Plugin.kt` | `PluginService.swift`, `NuvioJSRuntime.swift`, `SettingsView.swift`, `StreamResolver.swift` | Partial | iOS can add/refresh/remove repositories, download/cache Nuvio JS scrapers, toggle executable JS scrapers, and feed their streams into source resolution. External DEX execution is Android-only. JavaScriptCore runtime needs TestFlight/provider verification against real scraper repos. |
| Home server | `HomeServerRepository.kt`, settings home server section | `HomeServerService.swift`, `SettingsView.swift`, `StreamResolver.swift` | Partial | Verify Jellyfin/Plex connect/test/sync/catalog/source matching and Plex PIN flow parity. |
| Live TV/IPTV | `IptvRepository.kt`, `LiveTvScreen.kt`, `EpgGrid.kt`, `FullscreenGuideOverlay.kt`, category/sidebar/hud/miniplayer | `IptvService.swift`, `LiveTVView.swift`, `SettingsView.swift`, `HomeView.swift` | Partial | iOS supports M3U/Xtream/Stalker, EPG, search, favorites, hidden groups, group ordering, playlist enable/disable/remove/reorder, provider diagnostics from Settings and Live TV, VOD matching, playback headers, mini-player preview, fullscreen guide overlay, M3U/Xtream catchup metadata, and EPG replay URL generation. Needs real provider verification for catchup candidates, fullscreen behavior, and large-guide performance. |
| Telegram | `TelegramRepository.kt`, `TelegramSettingsScreen.kt`, `TelegramSourceResolver.kt`, account settings | No iOS equivalent yet | Missing | Add Telegram settings/service/source flow or document platform/security blocker after investigation. |
| Settings IA | `SettingsScreen.kt` sections: accounts, profiles, playback, language, subtitles, AI subtitles, IPTV, Stremio, catalogs, home server, plugins, appearance, network | `SettingsView.swift`, `SettingsService.swift` | Partial | iOS Settings now uses Android-style section navigation with a persistent tablet sidebar and compact phone section strip, plus accounts, profiles, Live TV/IPTV, sources, playback, subtitles, appearance, network, catalogs, and sync sections. Needs iPad/iPhone screenshot comparison and real form-flow verification. |
| General settings | `SettingsViewModel.kt`: card layout, autoplay, trailer, budget, smooth scrolling, spoiler blur, loading stats, OLED, clock, accent, device mode | `SettingsService.swift`, `SettingsView.swift` | Partial | Added trailer delay, OLED, smooth scrolling, accent, loading stats, and cloud round-trip. Device mode override remains Android-specific/needs iOS UX decision. |
| Network settings | DNS provider, custom User-Agent, loading stats | `SettingsService.swift`, `SettingsView.swift`, `StreamResolver.swift` | Partial | Added DNS/User-Agent/loading stats UI and User-Agent source/playback plumbing. DNS override cannot be globally identical on iOS URLSession without a custom resolver/proxy. |
| Quality filters | `QualityFilterConfig`, settings add/update/toggle/delete/preset, stream filtering | `SettingsService.swift`, `SettingsView.swift`, `StreamResolver.swift` | Partial | iOS now supports preset selection, custom regex validation, add/edit/toggle/delete filter rows, and stream filtering. Needs device/provider verification that Android-synced filter JSON behaves identically across real source lists. |
| App updates | `AppUpdateRepository.kt`, `AppUpdateModal.kt`, APK installer, unknown sources | None | Android-only | iOS equivalent is TestFlight/App Store update path; no APK installer. |
| Account/privacy/delete | settings accounts, README/privacy site links | `SettingsView.swift` | Partial | iOS now exposes the ARVIO Cloud privacy/account deletion link. Needs real device open-link verification. |
| Launcher/TV-specific behavior | Android launcher, Leanback, DPAD focus, frame-rate matching, keep screen on | iOS focus/touch/keyboard only | Android-only | Use iOS focus/touch equivalents, not literal Android behavior. |

## Verification Gates

The goal is not complete until all non-Android-only rows are `Done` with evidence:

1. Android source audit is complete against latest `origin/main`.
2. iOS source implements the feature, button, state, and persistence path.
3. iOS build passes on macOS/TestFlight workflow.
4. iPad/iPhone UI screenshots cover main flows.
5. Real account/provider testing covers cloud login, profiles, Trakt, watchlist, continue watching, addons, source resolution, playback, subtitles, home server, IPTV/EPG/favorites.
