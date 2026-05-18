import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    @State private var details: TmdbDetails?
    @State private var recommendations: [MediaItem] = []
    @State private var episodes: [TmdbEpisode] = []
    @State private var cast: [TmdbCastMember] = []
    @State private var trailerURL: URL?
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1

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
                                Task { await resolveSelectedSource(autoPlay: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ArvioTheme.gold)

                            Button("Watchlist") {
                                Task { await appState.trakt.addToWatchlist(item: item) }
                            }
                                .buttonStyle(.bordered)
                            Button("Mark Watched") {
                                Task { await appState.trakt.markWatched(item: currentPlaybackItem) }
                            }
                            .buttonStyle(.bordered)
                            if let trailerURL {
                                Link("Trailer", destination: trailerURL)
                                    .buttonStyle(.bordered)
                            }
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
                    .onChange(of: selectedSeason) { _, value in
                        selectedEpisode = 1
                        Task { await loadEpisodes(season: value) }
                    }

                    episodeGrid
                }

                SourceSelector()

                if !cast.isEmpty {
                    castRail
                }

                if !recommendations.isEmpty {
                    MediaRail(title: "More Like This", items: recommendations)
                }
            }
            .padding(28)
        }
        .task {
            selectedSeason = item.season ?? selectedSeason
            selectedEpisode = item.episode ?? selectedEpisode
            async let loadedDetails = try? appState.tmdb.details(for: item)
            async let loadedRecommendations = try? appState.tmdb.recommendations(for: item)
            async let loadedCast = try? appState.tmdb.cast(for: item)
            async let loadedTrailer = try? appState.tmdb.trailerURL(for: item)
            details = await loadedDetails ?? details
            recommendations = await loadedRecommendations ?? []
            cast = await loadedCast ?? []
            trailerURL = await loadedTrailer ?? trailerURL
            if item.kind == .series {
                await loadEpisodes(season: selectedSeason)
            }
        }
    }

    private var episodeGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Episodes")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(episodes) { episode in
                    Button {
                        selectedEpisode = episode.episodeNumber
                        Task { await resolveSelectedSource(autoPlay: false) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("E\(episode.episodeNumber)")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(episode.episodeNumber == selectedEpisode ? ArvioTheme.gold : ArvioTheme.textSecondary))
                                Spacer()
                                if let runtime = episode.runtime, runtime > 0 {
                                    Text("\(runtime)m")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ArvioTheme.textTertiary)
                                }
                            }
                            Text(episode.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                                .lineLimit(2)
                            Text(episode.overview ?? episode.airDate ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(ArvioTheme.textSecondary)
                                .lineLimit(3)
                        }
                        .padding(14)
                        .frame(minHeight: 132, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(episode.episodeNumber == selectedEpisode ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var castRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cast) { person in
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: person.imageURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.08)
                                }
                            }
                            .frame(width: 116, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(person.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                                .lineLimit(1)
                            Text(person.character ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(ArvioTheme.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(width: 116, alignment: .leading)
                    }
                }
            }
        }
    }

    private var currentPlaybackItem: MediaItem {
        guard item.kind == .series else { return item }
        return MediaItem(
            id: "\(item.id)-s\(selectedSeason)e\(selectedEpisode)",
            tmdbId: item.tmdbId,
            title: item.title,
            subtitle: item.subtitle,
            year: item.year,
            duration: item.duration,
            rating: item.rating,
            kind: item.kind,
            progress: item.progress,
            palette: item.palette,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            overview: item.overview,
            season: selectedSeason,
            episode: selectedEpisode,
            episodeTitle: episodes.first(where: { $0.episodeNumber == selectedEpisode })?.name,
            positionSeconds: item.positionSeconds,
            durationSeconds: item.durationSeconds
        )
    }

    private func loadEpisodes(season: Int) async {
        episodes = (try? await appState.tmdb.seasonEpisodes(for: item, season: season)) ?? []
    }

    private func resolveSelectedSource(autoPlay: Bool) async {
        appState.selectedMedia = currentPlaybackItem
        await appState.streams.resolve(item: currentPlaybackItem, season: selectedSeason, episode: selectedEpisode)
        let playable = appState.streams.streams.filter {
            $0.isPlayable && meetsMinimumQuality($0.quality, minimum: appState.settings.profileSettings.autoPlayMinQuality)
        }
        if autoPlay && appState.settings.profileSettings.autoPlaySingleSource, playable.count == 1 {
            appState.selectedStream = playable[0]
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
