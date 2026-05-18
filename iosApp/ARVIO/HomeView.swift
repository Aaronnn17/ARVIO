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
            await appState.catalogs.reloadRows()
        }
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
            Image("ARVIOTVBanner")
                .resizable()
                .scaledToFill()
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.86)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Image("ARVIOFeatureGraphic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260)
                    .padding(.bottom, 2)

                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)

                Text("\(item.subtitle)  -  \(item.year)  -  \(item.duration)")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)

                Text("A premium media hub experience for browsing, tracking and continuing your library across screens.")
                    .font(.system(size: 17))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 580, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        appState.selectedMedia = item
                    } label: {
                        PrimaryButton(title: "Open Details")
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await appState.trakt.addToWatchlist(item: item) }
                    } label: {
                        SecondaryButton(title: "Add to Watchlist")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(28)
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
