import Foundation

struct WatchHistoryEntry: Decodable, Identifiable, Hashable {
    let id: String?
    let userId: String?
    let profileId: String?
    let mediaType: String
    let showTmdbId: Int
    let season: Int?
    let episode: Int?
    let title: String?
    let episodeTitle: String?
    let progress: Double
    let durationSeconds: Int?
    let positionSeconds: Int?
    let pausedAt: String?
    let updatedAt: String?
    let source: String?
    let backdropPath: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case profileId = "profile_id"
        case mediaType = "media_type"
        case showTmdbId = "show_tmdb_id"
        case season
        case episode
        case title
        case episodeTitle = "episode_title"
        case progress
        case durationSeconds = "duration_seconds"
        case positionSeconds = "position_seconds"
        case pausedAt = "paused_at"
        case updatedAt = "updated_at"
        case source
        case backdropPath = "backdrop_path"
        case posterPath = "poster_path"
    }

    var stableId: String {
        id ?? "\(mediaType)-\(showTmdbId)-\(season ?? 0)-\(episode ?? 0)-\(updatedAt ?? "")"
    }

    func asMediaItem() -> MediaItem {
        let kind: MediaKind = mediaType == "movie" ? .movie : .series
        let seasonEpisode = season.flatMap { season in episode.map { "S\(season) E\($0)" } }
        let subtitle = [seasonEpisode, episodeTitle].compactMap { $0 }.joined(separator: " - ")
        return MediaItem(
            id: stableId,
            tmdbId: showTmdbId,
            title: title ?? "Continue Watching",
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.rawValue : subtitle,
            year: "",
            duration: positionLabel,
            rating: "",
            kind: kind,
            progress: progress,
            palette: ["#10202a", "#071017"],
            posterPath: posterPath,
            backdropPath: backdropPath,
            overview: nil,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
    }

    private var positionLabel: String {
        guard let positionSeconds, positionSeconds > 0 else { return "Resume" }
        return "\(positionSeconds / 60)m watched"
    }
}

struct TraktPlaybackItem: Decodable, Identifiable, Hashable {
    let id: Int?
    let progress: Double
    let pausedAt: String?
    let type: String
    let movie: TraktMedia?
    let show: TraktMedia?
    let episode: TraktEpisode?

    enum CodingKeys: String, CodingKey {
        case id
        case progress
        case pausedAt = "paused_at"
        case type
        case movie
        case show
        case episode
    }

    var stableId: String {
        "\(type)-\(movie?.ids.tmdb ?? show?.ids.tmdb ?? 0)-\(episode?.season ?? 0)-\(episode?.number ?? 0)"
    }

    func asMediaItem() -> MediaItem? {
        let normalizedProgress = min(max(progress / 100.0, 0), 1)
        if type == "movie", let movie, let tmdb = movie.ids.tmdb {
            return MediaItem(
                id: stableId,
                tmdbId: tmdb,
                title: movie.title,
                subtitle: "Trakt Continue Watching",
                year: movie.year.map(String.init) ?? "",
                duration: "\(Int(progress.rounded()))% watched",
                rating: "",
                kind: .movie,
                progress: normalizedProgress,
                palette: ["#10202a", "#071017"]
            )
        }
        if type == "episode", let show, let tmdb = show.ids.tmdb, let episode {
            return MediaItem(
                id: stableId,
                tmdbId: tmdb,
                title: show.title,
                subtitle: "S\(episode.season) E\(episode.number) - \(episode.title ?? "Episode")",
                year: show.year.map(String.init) ?? "",
                duration: "\(Int(progress.rounded()))% watched",
                rating: "",
                kind: .series,
                progress: normalizedProgress,
                palette: ["#10202a", "#071017"],
                season: episode.season,
                episode: episode.number,
                episodeTitle: episode.title
            )
        }
        return nil
    }
}

struct TraktMedia: Decodable, Hashable {
    let title: String
    let year: Int?
    let ids: TraktIds
}

struct TraktEpisode: Decodable, Hashable {
    let season: Int
    let number: Int
    let title: String?
    let ids: TraktIds?
}

struct TraktIds: Decodable, Hashable {
    let trakt: Int?
    let tmdb: Int?
    let imdb: String?
}

private struct WatchHistoryUpsert: Encodable {
    let userId: String
    let profileId: String
    let mediaType: String
    let showTmdbId: Int?
    let season: Int?
    let episode: Int?
    let progress: Double
    let positionSeconds: Int
    let durationSeconds: Int
    let pausedAt: String
    let updatedAt: String
    let source: String
    let title: String
    let episodeTitle: String?
    let backdropPath: String?
    let posterPath: String?
    let streamKey: String?
    let streamAddonId: String?
    let streamTitle: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profileId = "profile_id"
        case mediaType = "media_type"
        case showTmdbId = "show_tmdb_id"
        case season
        case episode
        case progress
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case pausedAt = "paused_at"
        case updatedAt = "updated_at"
        case source
        case title
        case episodeTitle = "episode_title"
        case backdropPath = "backdrop_path"
        case posterPath = "poster_path"
        case streamKey = "stream_key"
        case streamAddonId = "stream_addon_id"
        case streamTitle = "stream_title"
    }
}

@MainActor
final class WatchHistoryService: ObservableObject {
    @Published private(set) var cloudContinueWatching: [MediaItem] = []
    @Published private(set) var traktContinueWatching: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let auth: AuthService
    private let trakt: TraktService
    private var activeProfileId = "default"

    init(auth: AuthService, trakt: TraktService) {
        self.auth = auth
        self.trakt = trakt
    }

    var continueWatching: [MediaItem] {
        var seen = Set<String>()
        return (traktContinueWatching + cloudContinueWatching).filter { item in
            let key = "\(item.kind.rawValue)-\(item.tmdbId ?? 0)-\(item.season ?? 0)-\(item.episode ?? 0)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    func setActiveProfileId(_ profileId: String?) {
        let trimmed = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = trimmed.isEmpty ? "default" : trimmed
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadCloudContinueWatching()
        await loadTraktContinueWatching()
    }

    func loadCloudContinueWatching() async {
        guard let session = auth.session else { return }
        do {
            let token = try await auth.accessToken()
            let rows: [WatchHistoryEntry] = try await auth.supabaseRequest(
                "/rest/v1/watch_history?user_id=eq.\(session.userId)&select=*&order=updated_at.desc&limit=500",
                token: token
            )
            cloudContinueWatching = rows
                .filter { isInActiveProfile($0) }
                .filter { $0.progress > 0 && $0.progress < 0.9 }
                .map { $0.asMediaItem() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraktContinueWatching() async {
        guard trakt.isConnected else {
            traktContinueWatching = []
            return
        }
        do {
            let items = try await trakt.loadPlaybackProgress()
            traktContinueWatching = items.compactMap { $0.asMediaItem() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProgress(item: MediaItem, stream: ResolvedStream, positionSeconds: Int, durationSeconds: Int) async {
        guard let session = auth.session, durationSeconds > 0, positionSeconds > 0 else { return }
        let progress = min(max(Double(positionSeconds) / Double(durationSeconds), 0), 1)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let record = WatchHistoryUpsert(
            userId: session.userId,
            profileId: activeProfileId,
            mediaType: item.kind == .movie ? "movie" : "tv",
            showTmdbId: item.tmdbId,
            season: item.kind == .series ? item.season : nil,
            episode: item.kind == .series ? item.episode : nil,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            pausedAt: timestamp,
            updatedAt: timestamp,
            source: "arvio",
            title: item.title,
            episodeTitle: item.episodeTitle,
            backdropPath: item.backdropPath,
            posterPath: item.posterPath,
            streamKey: stream.url?.absoluteString,
            streamAddonId: stream.addonId,
            streamTitle: stream.title
        )
        do {
            let token = try await auth.accessToken()
            let _: EmptyResponse = try await auth.supabaseRequest(
                "/rest/v1/watch_history",
                method: "POST",
                token: token,
                prefer: "return=minimal,resolution=merge-duplicates",
                body: record
            )
            try? await trakt.scrobblePause(item: item, progressPercent: progress * 100)
            await load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isInActiveProfile(_ entry: WatchHistoryEntry) -> Bool {
        if let profileId = entry.profileId, !profileId.isEmpty {
            return profileId == activeProfileId
        }
        if let source = entry.source, source.hasPrefix("profile:") {
            return source.hasPrefix("profile:\(activeProfileId):")
        }
        return activeProfileId == "default"
    }
}
