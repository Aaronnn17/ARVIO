import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: WatchlistFilter = .all
    @State private var searchText = ""
    @State private var hydratedItems: [String: MediaItem] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watchlist")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(appState.trakt.isConnected ? "Synced from Trakt." : "Connect Trakt in Settings to sync your Android watchlist.")
                            .font(.system(size: 17))
                            .foregroundStyle(ArvioTheme.textSecondary)
                    }
                    Spacer()
                    Button("Refresh") {
                        Task { await appState.trakt.loadWatchlist() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                }

                HStack(spacing: 12) {
                    Picker("Filter", selection: $filter) {
                        ForEach(WatchlistFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)

                    TextField("Search watchlist", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .padding(13)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                        .foregroundStyle(ArvioTheme.textPrimary)
                }

                if appState.trakt.watchlist.isEmpty {
                    EmptyStatePanel(
                        title: "No synced watchlist yet",
                        message: appState.trakt.isConnected ? "Trakt returned no saved items." : "Your Android watchlist syncs here after Trakt is connected."
                    )
                } else if filteredItems.isEmpty {
                    EmptyStatePanel(title: "No matches", message: "Change the filter or search text.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                        ForEach(filteredItems) { item in
                            let media = mediaItem(for: item)
                            VStack(alignment: .leading, spacing: 10) {
                                PosterBackdrop(item: media)
                                    .frame(width: 210, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(1)
                                Text(([item.type.capitalized] + (item.year.map { [String($0)] } ?? [])).joined(separator: " - "))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                HStack(spacing: 8) {
                                    Button("Open") {
                                        appState.selectedMedia = media
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(ArvioTheme.gold)
                                    Button("Remove") {
                                        Task { await appState.trakt.removeFromWatchlist(item: item) }
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedMedia = media
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .task(id: appState.trakt.watchlist.map(\.cacheKey).joined(separator: "|")) {
            await hydrateVisibleItems()
        }
    }

    private var filteredItems: [TraktWatchlistItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.trakt.watchlist.filter { item in
            filter.matches(item) &&
                (query.isEmpty || item.title.lowercased().contains(query) || String(item.year ?? 0).contains(query))
        }
    }

    private func mediaItem(for item: TraktWatchlistItem) -> MediaItem {
        hydratedItems[item.cacheKey] ?? item.asMediaItem()
    }

    private func hydrateVisibleItems() async {
        let snapshot = appState.trakt.watchlist
        var resolved: [String: MediaItem] = [:]
        for item in snapshot.prefix(80) {
            guard let tmdbId = item.tmdbId else { continue }
            if let media = try? await appState.tmdb.itemDetails(
                tmdbId: tmdbId,
                kind: item.type == "movie" ? .movie : .series
            ) {
                resolved[item.cacheKey] = media
            }
        }
        hydratedItems = resolved
    }
}

private enum WatchlistFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }

    func matches(_ item: TraktWatchlistItem) -> Bool {
        switch self {
        case .all: return true
        case .movies: return item.type == "movie"
        case .series: return item.type == "show"
        }
    }
}

private extension TraktWatchlistItem {
    var cacheKey: String {
        "\(type)-\(tmdbId ?? 0)-\(title)"
    }
}

struct EmptyStatePanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(ArvioTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}
