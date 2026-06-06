import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: WatchlistFilter = .all
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watchlist")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(appState.trakt.isConnected ? "Profile watchlist with Trakt sync." : "Profile watchlist synced through ARVIO cloud.")
                            .font(.system(size: 17))
                            .foregroundStyle(ArvioTheme.textSecondary)
                    }
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await appState.watchlist.load()
                            await appState.trakt.loadWatchlist()
                        }
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

                if mergedItems.isEmpty {
                    EmptyStatePanel(
                        title: "No saved items yet",
                        message: "Add a movie or series from Home, Search, or Details. Trakt items appear here too when linked."
                    )
                } else if filteredItems.isEmpty {
                    EmptyStatePanel(title: "No matches", message: "Change the filter or search text.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                        ForEach(filteredItems) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                PosterBackdrop(item: item)
                                    .frame(width: 210, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(1)
                                Text([item.kind.rawValue, item.year.nilIfBlank].compactMap { $0 }.joined(separator: " - "))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                HStack(spacing: 8) {
                                    Button("Open") {
                                        appState.selectedMedia = item
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(ArvioTheme.gold)
                                    Button("Remove") {
                                        Task {
                                            await appState.watchlist.remove(item)
                                            await appState.trakt.removeFromWatchlist(item: item)
                                        }
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedMedia = item
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .task {
            await appState.watchlist.load()
            await appState.trakt.loadWatchlist()
        }
    }

    private var mergedItems: [MediaItem] {
        appState.watchlist.mergedWithTrakt(appState.trakt.watchlist)
    }

    private var filteredItems: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return mergedItems.filter { item in
            filter.matches(item) &&
                (query.isEmpty || item.title.lowercased().contains(query) || item.year.contains(query))
        }
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

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .movies: return item.kind == .movie
        case .series: return item.kind == .series
        }
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
