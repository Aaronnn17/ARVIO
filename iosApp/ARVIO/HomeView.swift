import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let hero = appState.watchHistory.continueWatching.first ?? appState.catalogs.rows.first?.items.first ?? appState.tmdb.trendingMovies.first {
                    HeroSection(item: hero)
                } else {
                    BrandHeroSection()
                }
                if !appState.watchHistory.continueWatching.isEmpty {
                    MediaRail(title: "Continue Watching", items: appState.watchHistory.continueWatching)
                }
                if !favoriteChannels.isEmpty {
                    LiveChannelRail(title: "Favorite Channels", channels: favoriteChannels)
                }
                ForEach(collectionRails) { rail in
                    let collections = collectionCatalogs(for: rail)
                    if !collections.isEmpty {
                        CollectionCatalogRail(title: rail.title, collections: collections)
                    }
                }
                if appState.catalogs.isLoading && appState.catalogs.rows.isEmpty {
                    EmptyStatePanel(title: "Loading catalogs", message: "Syncing your Android catalog rows from ARVIO cloud.")
                }
                ForEach(appState.catalogs.rows) { row in
                    MediaRail(title: row.config.title, items: row.items, catalog: row.config)
                }
                if appState.catalogs.rows.isEmpty {
                    MediaRail(title: "Trending Movies", items: appState.tmdb.trendingMovies)
                    MediaRail(title: "Trending Series", items: appState.tmdb.trendingSeries)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .refreshable {
            await appState.watchHistory.load()
            await loadLiveTVIfNeeded()
            await appState.catalogs.reloadRows()
        }
        .task {
            await loadLiveTVIfNeeded()
        }
    }

    private var favoriteChannels: [IptvChannel] {
        appState.iptv.channels.filter { channel in
            appState.iptv.state.favoriteChannels.contains(channel.id) ||
                appState.iptv.state.favoriteGroups.contains(channel.group)
        }
    }

    private var collectionRails: [CatalogConfig] {
        appState.catalogs.catalogs.filter { $0.kind == .collectionRail }
    }

    private func collectionCatalogs(for rail: CatalogConfig) -> [CatalogConfig] {
        appState.catalogs.catalogs.filter { catalog in
            catalog.kind == .collection &&
                catalog.collectionGroup == rail.collectionGroup
        }
    }

    private func loadLiveTVIfNeeded() async {
        guard appState.iptv.channels.isEmpty else { return }
        guard !appState.iptv.state.m3uUrl.isEmpty ||
            !appState.iptv.state.stalkerPortalUrl.isEmpty ||
            !appState.iptv.state.playlists.isEmpty else { return }
        await appState.iptv.reload()
    }
}

struct CollectionCatalogRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let collections: [CatalogConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(collections) { collection in
                        Button {
                            appState.selectedCatalog = collection
                        } label: {
                            CollectionCatalogCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct CollectionCatalogCard: View {
    let collection: CatalogConfig

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [ArvioTheme.panel, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(colors: [.clear, Color.black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            if !collection.collectionHideTitle {
                Text(collection.title)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(2)
                    .padding(14)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private var coverURL: URL? {
        [collection.collectionCoverImageUrl, collection.collectionHeroImageUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap(URL.init(string:))
    }

    private var width: CGFloat {
        collection.collectionTileShape == .poster ? 150 : 260
    }

    private var height: CGFloat {
        collection.collectionTileShape == .poster ? 225 : 146
    }
}

struct BrandHeroSection: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("ARVIOTVBanner")
                .resizable()
                .scaledToFill()
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.86)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Image("ARVIOFeatureGraphic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260)
                Text("ARVIO")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
            }
            .padding(28)
        }
    }
}

struct HeroSection: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("ARVIOTVBanner")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            LinearGradient(colors: [Color.black.opacity(0.04), Color.black.opacity(0.35), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            LinearGradient(colors: [Color.black.opacity(0.78), Color.black.opacity(0.0)], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: 680, alignment: .leading)

                Text(heroMetadata)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)

                Text(item.overview?.nilIfBlank ?? item.episodeTitle?.nilIfBlank ?? item.subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: 660, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        Task { await playHero() }
                    } label: {
                        PrimaryButton(title: item.positionSeconds.map { $0 > 30 ? "Resume" : "Play" } ?? "Play")
                    }
                    .buttonStyle(.plain)
                    Button {
                        appState.selectedMedia = item
                    } label: {
                        SecondaryButton(title: "Details")
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await toggleWatchlist() }
                    } label: {
                        SecondaryButton(title: appState.trakt.isInWatchlist(item) ? "In Watchlist" : "Watchlist")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
    }

    private var heroMetadata: String {
        [
            item.kind == .movie ? "Movie" : "Series",
            item.seasonEpisodeLabel,
            item.year.nilIfBlank,
            item.duration.nilIfBlank,
            item.rating.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private func playHero() async {
        appState.selectedMedia = item
        await appState.streams.resolve(item: item, season: item.season ?? 1, episode: item.episode ?? 1)
        guard appState.settings.profileSettings.autoPlaySingleSource,
              let stream = appState.streams.streams.first(where: \.isPlayable) else {
            return
        }
        appState.selectedStream = stream
    }

    private func toggleWatchlist() async {
        if appState.trakt.isInWatchlist(item) {
            await appState.trakt.removeFromWatchlist(item: item)
        } else {
            await appState.trakt.addToWatchlist(item: item)
        }
    }
}

struct MediaRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let items: [MediaItem]
    var catalog: CatalogConfig? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
                if let catalog {
                    Button("View All") {
                        appState.selectedCatalog = catalog
                    }
                    .buttonStyle(.bordered)
                    .tint(ArvioTheme.gold)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if items.isEmpty {
                        EmptyStatePanel(title: "Nothing here yet", message: "Content will appear here after sync finishes.")
                    }
                    ForEach(items) { item in
                        MediaCard(item: item, layout: layout) { selected in
                            appState.selectedMedia = selected
                        }
                    }
                }
            }
        }
    }

    private var layout: String {
        guard let catalog else { return appState.settings.profileSettings.cardLayoutMode }
        return appState.settings.profileSettings.catalogueRowLayoutModes[catalog.id]
            ?? (catalog.collectionTileShape == .poster ? "Portrait" : appState.settings.profileSettings.cardLayoutMode)
    }
}

struct LiveChannelRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let channels: [IptvChannel]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(channels.prefix(24)) { channel in
                        Button {
                            play(channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AsyncImage(url: channel.logo.flatMap(URL.init(string:))) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Image("ARVIOAppIcon").resizable().scaledToFit().opacity(0.8)
                                    }
                                }
                                .frame(width: 54, height: 54)
                                Text(channel.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(2)
                                Text(channel.group)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                    .lineLimit(1)
                                Spacer()
                                Text(appState.iptv.nowNextByChannelId[channel.id]?.now?.title ?? "LIVE")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(ArvioTheme.gold)
                                    .lineLimit(1)
                            }
                            .padding(14)
                            .frame(width: 210, height: 150, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func play(_ channel: IptvChannel) {
        appState.iptv.markOpened(channel)
        appState.selectedStream = ResolvedStream(
            addonId: nil,
            addonName: "Live TV",
            sourceName: channel.group,
            title: channel.name,
            quality: "Live",
            size: "",
            url: URL(string: channel.streamUrl),
            requestHeaders: [:],
            subtitles: [],
            isPlayable: true,
            resumePositionSeconds: nil
        )
    }
}

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let subtitle: String
    let items: [MediaItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(ArvioTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    if items.isEmpty {
                        EmptyStatePanel(title: "Nothing here yet", message: "Refresh or check your cloud connection.")
                    }
                    ForEach(items) { item in
                        MediaCard(item: item) { selected in
                            appState.selectedMedia = selected
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
    }
}

struct CatalogDetailView: View {
    @EnvironmentObject private var appState: AppState
    let config: CatalogConfig
    @State private var items: [MediaItem] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button("Back") { appState.selectedCatalog = nil }
                    .buttonStyle(.bordered)
                Text(config.title)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                if let description = config.collectionDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 17))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
                if isLoading {
                    ProgressView()
                        .tint(ArvioTheme.gold)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        MediaCard(item: item) { selected in
                            appState.selectedMedia = selected
                        }
                    }
                }
            }
            .padding(28)
        }
        .task(id: config.id) {
            isLoading = true
            items = await appState.catalogs.items(for: config)
            isLoading = false
        }
    }
}

private extension MediaItem {
    var seasonEpisodeLabel: String? {
        guard kind == .series else { return nil }
        if let season, let episode {
            return "S\(season) E\(episode)"
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
