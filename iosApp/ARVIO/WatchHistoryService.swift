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
        id ?? "\(SharedCoreBridge.historyKey(mediaType: mediaType, tmdbId: showTmdbId, season: season, episode: episode))-\(updatedAt ?? "")"
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
        SharedCoreBridge.historyKey(
            mediaType: type == "movie" ? "movie" : "tv",
            tmdbId: movie?.ids.tmdb ?? show?.ids.tmdb ?? 0,
            season: episode?.season,
            episode: episode?.number
        )
    }

    func asMediaItem() -> MediaItem? {
        let normalizedProgress = SharedCoreBridge.progressFraction(percent: progress)
        guard SharedCoreBridge.shouldShowContinueWatching(progress: normalizedProgress) else { return nil }
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

struct CloudContinueWatchingItem: Codable, Hashable {
    let id: Int
    let title: String
    let mediaType: String
    let progress: Int
    let resumePositionSeconds: Int64
    let durationSeconds: Int64
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    let backdropPath: String?
    let posterPath: String?
    let streamKey: String?
    let streamAddonId: String?
    let streamTitle: String?
    let year: String
    let updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mediaType
        case progress
        case resumePositionSeconds
        case durationSeconds
        case season
        case episode
        case episodeTitle
        case backdropPath
        case posterPath
        case streamKey
        case streamAddonId
        case streamTitle
        case year
        case updatedAtMs
    }

    init(
        id: Int,
        title: String,
        mediaType: String,
        progress: Int,
        resumePositionSeconds: Int64,
        durationSeconds: Int64,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        backdropPath: String? = nil,
        posterPath: String? = nil,
        streamKey: String? = nil,
        streamAddonId: String? = nil,
        streamTitle: String? = nil,
        year: String = "",
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.mediaType = Self.androidMediaType(mediaType)
        self.progress = progress
        self.resumePositionSeconds = resumePositionSeconds
        self.durationSeconds = durationSeconds
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.backdropPath = backdropPath
        self.posterPath = posterPath
        self.streamKey = streamKey
        self.streamAddonId = streamAddonId
        self.streamTitle = streamTitle
        self.year = year
        self.updatedAtMs = updatedAtMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        title = (try? container.decode(String.self, forKey: .title)) ?? "Continue Watching"
        mediaType = Self.androidMediaType((try? container.decode(String.self, forKey: .mediaType)) ?? "TV")
        progress = (try? container.decode(Int.self, forKey: .progress)) ?? 0
        resumePositionSeconds = Self.decodeInt64(container, .resumePositionSeconds)
        durationSeconds = Self.decodeInt64(container, .durationSeconds)
        season = try? container.decode(Int.self, forKey: .season)
        episode = try? container.decode(Int.self, forKey: .episode)
        episodeTitle = try? container.decode(String.self, forKey: .episodeTitle)
        backdropPath = try? container.decode(String.self, forKey: .backdropPath)
        posterPath = try? container.decode(String.self, forKey: .posterPath)
        streamKey = try? container.decode(String.self, forKey: .streamKey)
        streamAddonId = try? container.decode(String.self, forKey: .streamAddonId)
        streamTitle = try? container.decode(String.self, forKey: .streamTitle)
        year = (try? container.decode(String.self, forKey: .year)) ?? ""
        updatedAtMs = Self.decodeInt64(container, .updatedAtMs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(progress, forKey: .progress)
        try container.encode(resumePositionSeconds, forKey: .resumePositionSeconds)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(season, forKey: .season)
        try container.encodeIfPresent(episode, forKey: .episode)
        try container.encodeIfPresent(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(backdropPath, forKey: .backdropPath)
        try container.encodeIfPresent(posterPath, forKey: .posterPath)
        try container.encodeIfPresent(streamKey, forKey: .streamKey)
        try container.encodeIfPresent(streamAddonId, forKey: .streamAddonId)
        try container.encodeIfPresent(streamTitle, forKey: .streamTitle)
        try container.encode(year, forKey: .year)
        try container.encode(updatedAtMs, forKey: .updatedAtMs)
    }

    func asMediaItem() -> MediaItem? {
        guard id > 0 else { return nil }
        let kind: MediaKind = Self.normalizedMediaType(mediaType) == "movie" ? .movie : .series
        let duration = resumePositionSeconds > 0 ? "\(Int(resumePositionSeconds / 60))m watched" : "Continue"
        return MediaItem(
            id: "cloud-cw-\(mediaType)-\(id)-\(season ?? 0)-\(episode ?? 0)",
            tmdbId: id,
            title: title,
            subtitle: season.flatMap { season in episode.map { "S\(season) E\($0)" } } ?? kind.rawValue,
            year: year,
            duration: duration,
            rating: "",
            kind: kind,
            progress: Double(progress) / 100.0,
            palette: ["#10202a", "#071017"],
            posterPath: posterPath,
            backdropPath: backdropPath,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
            positionSeconds: Int(resumePositionSeconds),
            durationSeconds: Int(durationSeconds)
        )
    }

    private static func normalizedMediaType(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "movie" || value == "movies" ? "movie" : "tv"
    }

    private static func androidMediaType(_ raw: String) -> String {
        normalizedMediaType(raw) == "movie" ? "MOVIE" : "TV"
    }

    private static func decodeInt64(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64 {
        if let value = try? container.decode(Int64.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? container.decode(Double.self, forKey: key) { return Int64(value) }
        return 0
    }
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
    @Published private(set) var localContinueWatching: [MediaItem] = []
    @Published private(set) var traktContinueWatching: [MediaItem] = []
    @Published private(set) var watchedMovieIds: Set<Int> = []
    @Published private(set) var watchedEpisodeKeys: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let auth: AuthService
    private let cloud: CloudSyncService
    private let trakt: TraktService
    private var activeProfileId = "default"
    private var dismissedContinueWatchingRaw = ""
    private var localContinueWatchingRecords: [CloudContinueWatchingItem] = []

    init(auth: AuthService, cloud: CloudSyncService, trakt: TraktService) {
        self.auth = auth
        self.cloud = cloud
        self.trakt = trakt
    }

    var continueWatching: [MediaItem] {
        var seen = Set<String>()
        return (traktContinueWatching + cloudContinueWatching + localContinueWatching).filter { item in
            let key = SharedCoreBridge.historyKey(
                mediaType: item.kind.tmdbPath,
                tmdbId: item.tmdbId ?? 0,
                season: item.season,
                episode: item.episode
            )
            if seen.contains(key) || isDismissed(item) { return false }
            seen.insert(key)
            return true
        }
    }

    func setActiveProfileId(_ profileId: String?) {
        let trimmed = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = trimmed.isEmpty ? "default" : trimmed
        loadDismissedAndLocalFromCloud()
        loadWatchedFromCloud()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        loadDismissedAndLocalFromCloud()
        loadWatchedFromCloud()
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
                .filter { SharedCoreBridge.shouldShowContinueWatching(progress: $0.progress) }
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
        guard SharedCoreBridge.shouldSaveProgress(positionSeconds: positionSeconds, durationSeconds: durationSeconds) else { return }
        let progress = SharedCoreBridge.progressFraction(positionSeconds: positionSeconds, durationSeconds: durationSeconds)
        try? await trakt.scrobblePause(item: item, progressPercent: progress * 100)
        await upsertLocalContinueWatching(
            item: item,
            stream: stream,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        guard let session = auth.session else {
            await loadTraktContinueWatching()
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let record = WatchHistoryUpsert(
            userId: session.userId,
            profileId: activeProfileId,
            mediaType: item.kind.tmdbPath,
            showTmdbId: item.tmdbId,
            season: item.kind == .series ? item.season : nil,
            episode: item.kind == .series ? item.episode : nil,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            pausedAt: timestamp,
            updatedAt: timestamp,
            source: "profile:\(activeProfileId):arvio",
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
            await load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismiss(_ item: MediaItem) async {
        var dismissed = parseDismissedMap(dismissedContinueWatchingRaw)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for key in dismissalKeys(for: item) {
            dismissed[key] = now
        }
        dismissedContinueWatchingRaw = encodeDismissedMap(dismissed)
        removeVisible(item)
        await cloud.save(dismissedContinueWatchingRaw: dismissedContinueWatchingRaw, profileId: activeProfileId)
        await deleteCloudHistory(item)
    }

    func markWatched(_ item: MediaItem) async {
        guard let tmdbId = item.tmdbId else { return }
        if item.kind == .movie {
            watchedMovieIds.insert(tmdbId)
            removeVisible(item)
        } else if let season = item.season, let episode = item.episode {
            watchedEpisodeKeys.insert(Self.episodeWatchedKey(tmdbId: tmdbId, season: season, episode: episode))
            removeVisible(item)
        }
        saveWatchedLocal()
        await cloud.save(localContinueWatching: localContinueWatchingRecords, profileId: activeProfileId)
        await cloud.save(
            localWatchedMovies: Array(watchedMovieIds).sorted(),
            localWatchedEpisodes: Array(watchedEpisodeKeys).sorted(),
            profileId: activeProfileId
        )
    }

    func toggleWatched(_ item: MediaItem) async {
        guard let tmdbId = item.tmdbId else { return }
        if isWatched(item) {
            if item.kind == .movie {
                watchedMovieIds.remove(tmdbId)
            } else if let season = item.season, let episode = item.episode {
                watchedEpisodeKeys.remove(Self.episodeWatchedKey(tmdbId: tmdbId, season: season, episode: episode))
            }
            saveWatchedLocal()
            await cloud.save(
                localWatchedMovies: Array(watchedMovieIds).sorted(),
                localWatchedEpisodes: Array(watchedEpisodeKeys).sorted(),
                profileId: activeProfileId
            )
        } else {
            await markWatched(item)
        }
    }

    func isWatched(_ item: MediaItem) -> Bool {
        guard let tmdbId = item.tmdbId else { return false }
        if item.kind == .movie {
            return watchedMovieIds.contains(tmdbId)
        }
        guard let season = item.season, let episode = item.episode else { return false }
        return watchedEpisodeKeys.contains(Self.episodeWatchedKey(tmdbId: tmdbId, season: season, episode: episode))
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

    private func loadDismissedAndLocalFromCloud() {
        dismissedContinueWatchingRaw = cloud.payload.dismissedContinueWatchingByProfile?[activeProfileId] ?? ""
        let localItems = trakt.isConnected ? [] :
            cloud.payload.localContinueWatchingByProfile?[activeProfileId] ?? loadLocalContinueWatchingRecords()
        localContinueWatchingRecords = localItems
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
            .prefix(50)
            .map { $0 }
        localContinueWatching = localContinueWatchingRecords
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
            .compactMap { $0.asMediaItem() }
    }

    private func loadWatchedFromCloud() {
        let localWatched = loadWatchedLocal()
        watchedMovieIds = Set(cloud.payload.localWatchedMoviesByProfile?[activeProfileId] ?? localWatched.movies)
        watchedEpisodeKeys = Set(cloud.payload.localWatchedEpisodesByProfile?[activeProfileId] ?? localWatched.episodes)
    }

    private func upsertLocalContinueWatching(item: MediaItem, stream: ResolvedStream, progress: Double, positionSeconds: Int, durationSeconds: Int) async {
        guard let tmdbId = item.tmdbId, tmdbId > 0 else { return }
        localContinueWatchingRecords.removeAll { existing in
            existing.id == tmdbId && CloudContinueWatchingItem.normalizedMediaTypeForComparison(existing.mediaType) == item.kind.tmdbPath
        }
        if SharedCoreBridge.shouldShowContinueWatching(progress: progress) {
            localContinueWatchingRecords.insert(
                CloudContinueWatchingItem(
                    id: tmdbId,
                    title: item.title,
                    mediaType: item.kind == .movie ? "MOVIE" : "TV",
                    progress: Int((progress * 100).rounded()).clamped(to: 0...100),
                    resumePositionSeconds: Int64(positionSeconds),
                    durationSeconds: Int64(durationSeconds),
                    season: item.kind == .series ? item.season : nil,
                    episode: item.kind == .series ? item.episode : nil,
                    episodeTitle: item.episodeTitle,
                    backdropPath: item.backdropPath,
                    posterPath: item.posterPath,
                    streamKey: stream.url?.absoluteString,
                    streamAddonId: stream.addonId,
                    streamTitle: stream.title,
                    year: item.year
                ),
                at: 0
            )
        }
        localContinueWatchingRecords = Array(localContinueWatchingRecords.prefix(50))
        localContinueWatching = localContinueWatchingRecords.compactMap { $0.asMediaItem() }
        saveLocalContinueWatchingRecords()
        if auth.session != nil {
            await cloud.save(localContinueWatching: localContinueWatchingRecords, profileId: activeProfileId)
        }
    }

    private func isDismissed(_ item: MediaItem) -> Bool {
        let dismissed = parseDismissedMap(dismissedContinueWatchingRaw)
        return dismissalKeys(for: item).contains { dismissed[$0] != nil }
    }

    private func dismissalKeys(for item: MediaItem) -> [String] {
        guard let tmdbId = item.tmdbId else { return [] }
        if item.kind == .movie {
            return ["movie:\(tmdbId)"]
        }
        var keys = ["tv:\(tmdbId)"]
        if let season = item.season, let episode = item.episode {
            keys.append("tv:\(tmdbId):\(season):\(episode)")
        }
        return keys
    }

    private func removeVisible(_ item: MediaItem) {
        let keys = Set(dismissalKeys(for: item))
        func keep(_ candidate: MediaItem) -> Bool {
            Set(dismissalKeys(for: candidate)).isDisjoint(with: keys)
        }
        cloudContinueWatching = cloudContinueWatching.filter(keep)
        traktContinueWatching = traktContinueWatching.filter(keep)
        localContinueWatching = localContinueWatching.filter(keep)
        localContinueWatchingRecords = localContinueWatchingRecords.filter { record in
            record.asMediaItem().map(keep) ?? false
        }
        saveLocalContinueWatchingRecords()
    }

    private func parseDismissedMap(_ raw: String) -> [String: Int64] {
        raw.split(separator: "|").reduce(into: [:]) { result, entry in
            guard let comma = entry.lastIndex(of: ",") else { return }
            let key = String(entry[..<comma])
            let value = Int64(entry[entry.index(after: comma)...]) ?? 0
            guard !key.isEmpty, value > 0 else { return }
            result[key] = value
        }
    }

    private func encodeDismissedMap(_ map: [String: Int64]) -> String {
        map.sorted { $0.key < $1.key }
            .map { "\($0.key),\($0.value)" }
            .joined(separator: "|")
    }

    private func deleteCloudHistory(_ item: MediaItem) async {
        guard let session = auth.session, let tmdbId = item.tmdbId else { return }
        do {
            let token = try await auth.accessToken()
            var parts = [
                "user_id=eq.\(session.userId)",
                "show_tmdb_id=eq.\(tmdbId)",
                "profile_id=eq.\(activeProfileId)"
            ]
            if item.kind == .series {
                if let season = item.season { parts.append("season=eq.\(season)") }
                if let episode = item.episode { parts.append("episode=eq.\(episode)") }
            }
            let _: EmptyResponse = try await auth.supabaseRequest(
                "/rest/v1/watch_history?\(parts.joined(separator: "&"))",
                method: "DELETE",
                token: token,
                prefer: "return=minimal"
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLocalContinueWatchingRecords() -> [CloudContinueWatchingItem] {
        guard let data = UserDefaults.standard.data(forKey: localContinueWatchingStorageKey),
              let decoded = try? JSONDecoder().decode([CloudContinueWatchingItem].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveLocalContinueWatchingRecords() {
        if localContinueWatchingRecords.isEmpty {
            UserDefaults.standard.removeObject(forKey: localContinueWatchingStorageKey)
            return
        }
        if let data = try? JSONEncoder().encode(localContinueWatchingRecords) {
            UserDefaults.standard.set(data, forKey: localContinueWatchingStorageKey)
        }
    }

    private var localContinueWatchingStorageKey: String {
        "arvio.ios.localContinueWatching.\(activeProfileId)"
    }

    private func loadWatchedLocal() -> (movies: [Int], episodes: [String]) {
        let defaults = UserDefaults.standard
        let movies = defaults.array(forKey: watchedMoviesStorageKey) as? [Int] ?? []
        let episodes = defaults.stringArray(forKey: watchedEpisodesStorageKey) ?? []
        return (movies, episodes)
    }

    private func saveWatchedLocal() {
        UserDefaults.standard.set(Array(watchedMovieIds).sorted(), forKey: watchedMoviesStorageKey)
        UserDefaults.standard.set(Array(watchedEpisodeKeys).sorted(), forKey: watchedEpisodesStorageKey)
    }

    private var watchedMoviesStorageKey: String {
        "arvio.ios.localWatchedMovies.\(activeProfileId)"
    }

    private var watchedEpisodesStorageKey: String {
        "arvio.ios.localWatchedEpisodes.\(activeProfileId)"
    }

    private static func episodeWatchedKey(tmdbId: Int, season: Int, episode: Int) -> String {
        "\(tmdbId):\(season):\(episode)"
    }
}

private extension CloudContinueWatchingItem {
    static func normalizedMediaTypeForComparison(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "movie" || value == "movies" ? "movie" : "tv"
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
