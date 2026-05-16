import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    @State private var details: TmdbDetails?
    @State private var recommendations: [MediaItem] = []
    @State private var selectedSeason = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    PosterBackdrop(item: item)
                        .frame(height: 420)
                    LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Button("Back") { appState.selectedMedia = nil }
                            .buttonStyle(.bordered)
                        Text(details?.title ?? details?.name ?? item.title)
                            .font(.system(size: 46, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(metadata)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ArvioTheme.textSecondary)
                        Text(details?.overview ?? item.overview ?? "")
                            .font(.system(size: 16))
                            .foregroundStyle(ArvioTheme.textSecondary)
                            .lineLimit(3)
                            .frame(maxWidth: 760, alignment: .leading)
                        HStack(spacing: 12) {
                            Button("Play") {
                                Task {
                                    await appState.streams.resolve(
                                        item: item,
                                        season: item.season ?? selectedSeason,
                                        episode: item.episode ?? 1
                                    )
                                    let playable = appState.streams.streams.filter {
                                        $0.isPlayable && meetsMinimumQuality($0.quality, minimum: appState.settings.profileSettings.autoPlayMinQuality)
                                    }
                                    if appState.settings.profileSettings.autoPlaySingleSource, playable.count == 1 {
                                        appState.selectedStream = playable[0]
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ArvioTheme.gold)

                            Button("Watchlist") {
                                Task { await appState.trakt.addToWatchlist(item: item) }
                            }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(28)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if item.kind == .series, let seasons = details?.seasons?.filter({ $0.seasonNumber > 0 }) {
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(seasons) { season in
                            Text(season.name ?? "Season \(season.seasonNumber)").tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SourceSelector()

                if !recommendations.isEmpty {
                    MediaRail(title: "More Like This", items: recommendations)
                }
            }
            .padding(28)
        }
        .task {
            selectedSeason = item.season ?? selectedSeason
            async let loadedDetails = try? appState.tmdb.details(for: item)
            async let loadedRecommendations = try? appState.tmdb.recommendations(for: item)
            details = await loadedDetails ?? details
            recommendations = await loadedRecommendations ?? []
        }
    }

    private var metadata: String {
        let year = details?.releaseDate?.prefix(4) ?? details?.firstAirDate?.prefix(4) ?? Substring(item.year)
        let rating = details?.voteAverage.map { String(format: "%.1f", $0) } ?? item.rating
        let genres = details?.genres?.prefix(3).map(\.name).joined(separator: ", ") ?? item.subtitle
        let runtime = details?.runtime.map { "\($0)m" } ??
            details?.episodeRunTime?.first.map { "\($0)m" } ??
            item.duration
        return [String(year), rating.isEmpty ? nil : "TMDB \(rating)", runtime.isEmpty ? nil : runtime, genres].compactMap { $0 }.joined(separator: " - ")
    }

    private func meetsMinimumQuality(_ quality: String, minimum: String) -> Bool {
        qualityRank(quality) >= qualityRank(minimum)
    }

    private func qualityRank(_ value: String) -> Int {
        if value.localizedCaseInsensitiveContains("4K") || value.contains("2160") { return 4 }
        if value.contains("1080") { return 3 }
        if value.contains("720") { return 2 }
        if value == "Any" || value == "Unknown" { return 0 }
        return 1
    }
}

struct SourceSelector: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sources")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
                if appState.streams.isLoading {
                    ProgressView()
                }
            }

            if let error = appState.streams.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if appState.streams.streams.isEmpty && !appState.streams.isLoading {
                EmptyStatePanel(
                    title: "No sources loaded",
                    message: appState.addons.addons.isEmpty ? "Install stream addons first." : "Press Play to resolve addon sources."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appState.streams.streams) { stream in
                        Button {
                            if stream.isPlayable {
                                appState.selectedStream = stream
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(stream.sourceName)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(ArvioTheme.textPrimary)
                                    Text([stream.addonName, stream.quality, stream.size, stream.isPlayable ? "Playable" : "Needs direct stream"].filter { !$0.isEmpty }.joined(separator: " - "))
                                        .font(.system(size: 13))
                                        .foregroundStyle(ArvioTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(stream.isPlayable ? ArvioTheme.gold.opacity(0.7) : ArvioTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!stream.isPlayable)
                    }
                }
            }
        }
    }
}
