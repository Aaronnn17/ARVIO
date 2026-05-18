import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var appState: AppState

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

                if appState.trakt.watchlist.isEmpty {
                    EmptyStatePanel(
                        title: "No synced watchlist yet",
                        message: appState.trakt.isConnected ? "Trakt returned no saved items." : "Your Android watchlist syncs here after Trakt is connected."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                        ForEach(appState.trakt.watchlist) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                PosterBackdrop(item: item.asMediaItem())
                                    .frame(width: 210, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(1)
                                Text(([item.type.capitalized] + (item.year.map { [String($0)] } ?? [])).joined(separator: " - "))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                Button("Remove") {
                                    Task { await appState.trakt.removeFromWatchlist(item: item) }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .buttonStyle(.bordered)
                            }
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedMedia = item.asMediaItem()
                            }
                        }
                    }
                }
            }
            .padding(28)
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
