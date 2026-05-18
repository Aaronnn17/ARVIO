import Foundation

struct TraktDeviceCode: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TraktToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt
    }
}

struct TraktWatchlistItem: Identifiable, Decodable, Hashable {
    let id = UUID()
    let type: String
    let title: String
    let year: Int?
    let tmdbId: Int?

    enum RootKeys: String, CodingKey {
        case type
        case movie
        case show
    }

    enum MediaKeys: String, CodingKey {
        case title
        case year
        case ids
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        type = try root.decode(String.self, forKey: .type)
        if let movie = try? root.nestedContainer(keyedBy: MediaKeys.self, forKey: .movie) {
            title = (try? movie.decode(String.self, forKey: .title)) ?? "Untitled"
            year = try? movie.decode(Int.self, forKey: .year)
            tmdbId = (try? movie.decode(TraktWatchlistIds.self, forKey: .ids))?.tmdb
        } else if let show = try? root.nestedContainer(keyedBy: MediaKeys.self, forKey: .show) {
            title = (try? show.decode(String.self, forKey: .title)) ?? "Untitled"
            year = try? show.decode(Int.self, forKey: .year)
            tmdbId = (try? show.decode(TraktWatchlistIds.self, forKey: .ids))?.tmdb
        } else {
            title = "Untitled"
            year = nil
            tmdbId = nil
        }
    }

    func asMediaItem() -> MediaItem {
        MediaItem(
            id: "\(type)-\(tmdbId ?? 0)-\(title)",
            tmdbId: tmdbId,
            title: title,
            subtitle: type.capitalized,
            year: year.map(String.init) ?? "",
            duration: "Trakt",
            rating: "",
            kind: type == "movie" ? .movie : .series,
            progress: 0,
            palette: ["#10202a", "#071017"]
        )
    }
}

struct CloudTraktToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?
}

private struct TraktWatchlistIds: Decodable {
    let tmdb: Int?
}

private struct DeviceCodeRequest: Encodable {
}

private struct DeviceTokenRequest: Encodable {
    let code: String
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
    let grantType = "refresh_token"

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case grantType = "grant_type"
    }
}

private struct DeviceTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TraktScrobbleMedia: Encodable {
    let ids: TraktScrobbleIds
}

private struct TraktScrobbleEpisode: Encodable {
    let season: Int
    let number: Int
}

private struct TraktScrobbleIds: Encodable {
    let tmdb: Int
}

private struct TraktScrobbleBody: Encodable {
    let movie: TraktScrobbleMedia?
    let show: TraktScrobbleMedia?
    let episode: TraktScrobbleEpisode?
    let progress: Double

    enum CodingKeys: String, CodingKey {
        case movie
        case show
        case episode
        case progress
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(movie, forKey: .movie)
        try container.encodeIfPresent(show, forKey: .show)
        try container.encodeIfPresent(episode, forKey: .episode)
        try container.encode(progress, forKey: .progress)
    }
}

private struct TraktWatchlistMutationBody: Encodable {
    let movies: [TraktScrobbleMedia]?
    let shows: [TraktScrobbleMedia]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(movies, forKey: .movies)
        try container.encodeIfPresent(shows, forKey: .shows)
    }

    enum CodingKeys: String, CodingKey {
        case movies
        case shows
    }
}

@MainActor
final class TraktService: ObservableObject {
    @Published private(set) var token: TraktToken?
    @Published private(set) var deviceCode: TraktDeviceCode?
    @Published private(set) var watchlist: [TraktWatchlistItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client = JSONClient()
    private let keychain = KeychainStore()
    private let tokenAccount = "trakt-token"
    private let cloud: CloudSyncService
    private var activeProfileId = "default"

    init(cloud: CloudSyncService) {
        self.cloud = cloud
        token = keychain.load(TraktToken.self, account: tokenAccount)
    }

    var isConnected: Bool {
        token != nil
    }

    func beginDeviceLink() async {
        guard AppConfig.isTraktConfigured else {
            errorMessage = "Trakt is not configured for iOS"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = proxyURL(path: "/oauth/device/code", method: "POST") else { return }
            deviceCode = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(),
                body: DeviceCodeRequest()
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pollForToken() async {
        guard let code = deviceCode?.deviceCode else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = proxyURL(path: "/oauth/device/token", method: "POST") else { return }
            let response: DeviceTokenResponse = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(),
                body: DeviceTokenRequest(code: code)
            )
            let newToken = TraktToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
            try keychain.save(newToken, account: tokenAccount)
            token = newToken
            await cloud.save(traktToken: newToken.asCloudToken, profileId: activeProfileId)
            deviceCode = nil
            errorMessage = nil
            await loadWatchlist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        token = nil
        watchlist = []
        deviceCode = nil
        keychain.delete(account: tokenAccount)
        Task { await cloud.save(traktToken: nil, profileId: activeProfileId) }
    }

    func setActiveProfileId(_ profileId: String?) {
        let resolved = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = resolved.isEmpty ? "default" : resolved
        loadFromCloud()
    }

    func loadFromCloud() {
        guard let cloudToken = cloud.payload.traktTokens?[activeProfileId] else { return }
        let expires = cloudToken.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ??
            Date().addingTimeInterval(3600)
        let restored = TraktToken(
            accessToken: cloudToken.accessToken,
            refreshToken: cloudToken.refreshToken ?? "",
            expiresAt: expires
        )
        token = restored
        try? keychain.save(restored, account: tokenAccount)
    }

    func loadWatchlist() async {
        guard let accessToken = await accessToken() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = proxyURL(path: "/sync/watchlist") else { return }
            watchlist = try await client.request(
                url,
                headers: proxyHeaders(userToken: accessToken)
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPlaybackProgress() async throws -> [TraktPlaybackItem] {
        guard let accessToken = await accessToken() else { return [] }
        guard let url = proxyURL(path: "/sync/playback") else { return [] }
        return try await client.request(
            url,
            headers: proxyHeaders(userToken: accessToken)
        )
    }

    func addToWatchlist(item: MediaItem) async {
        guard let accessToken = await accessToken(), let tmdbId = item.tmdbId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = proxyURL(path: "/sync/watchlist", method: "POST") else { return }
            let media = TraktScrobbleMedia(ids: TraktScrobbleIds(tmdb: tmdbId))
            let body = TraktWatchlistMutationBody(
                movies: item.kind == .movie ? [media] : nil,
                shows: item.kind == .series ? [media] : nil
            )
            let _: EmptyResponse = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(userToken: accessToken),
                body: body
            )
            await loadWatchlist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromWatchlist(item: TraktWatchlistItem) async {
        guard let accessToken = await accessToken(), let tmdbId = item.tmdbId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = proxyURL(path: "/sync/watchlist/remove", method: "POST") else { return }
            let media = TraktScrobbleMedia(ids: TraktScrobbleIds(tmdb: tmdbId))
            let body = TraktWatchlistMutationBody(
                movies: item.type == "movie" ? [media] : nil,
                shows: item.type == "show" ? [media] : nil
            )
            let _: EmptyResponse = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(userToken: accessToken),
                body: body
            )
            await loadWatchlist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scrobblePause(item: MediaItem, progressPercent: Double) async throws {
        guard let accessToken = await accessToken(), let tmdbId = item.tmdbId else { return }
        guard let url = proxyURL(path: "/scrobble/pause", method: "POST") else { return }
        let progress = min(max(progressPercent, 0), 100)
        let body: TraktScrobbleBody
        if item.kind == .movie {
            body = TraktScrobbleBody(
                movie: TraktScrobbleMedia(ids: TraktScrobbleIds(tmdb: tmdbId)),
                show: nil,
                episode: nil,
                progress: progress
            )
        } else {
            guard let season = item.season, let episode = item.episode else { return }
            body = TraktScrobbleBody(
                movie: nil,
                show: TraktScrobbleMedia(ids: TraktScrobbleIds(tmdb: tmdbId)),
                episode: TraktScrobbleEpisode(season: season, number: episode),
                progress: progress
            )
        }
        let _: EmptyResponse = try await client.request(
            url,
            method: "POST",
            headers: proxyHeaders(userToken: accessToken),
            body: body
        )
    }

    func markWatched(item: MediaItem) async {
        guard let accessToken = await accessToken(), let tmdbId = item.tmdbId else { return }
        do {
            guard let url = proxyURL(path: "/sync/history", method: "POST") else { return }
            let media = TraktScrobbleMedia(ids: TraktScrobbleIds(tmdb: tmdbId))
            let body = TraktWatchlistMutationBody(
                movies: item.kind == .movie ? [media] : nil,
                shows: item.kind == .series ? [media] : nil
            )
            let _: EmptyResponse = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(userToken: accessToken),
                body: body
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accessToken() async -> String? {
        guard let current = token else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 3600 || current.refreshToken.isEmpty {
            return current.accessToken
        }
        do {
            guard let url = proxyURL(path: "/oauth/token", method: "POST") else { return current.accessToken }
            let response: DeviceTokenResponse = try await client.request(
                url,
                method: "POST",
                headers: proxyHeaders(),
                body: RefreshTokenRequest(refreshToken: current.refreshToken)
            )
            let refreshed = TraktToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
            try keychain.save(refreshed, account: tokenAccount)
            token = refreshed
            await cloud.save(traktToken: refreshed.asCloudToken, profileId: activeProfileId)
            return refreshed.accessToken
        } catch {
            errorMessage = error.localizedDescription
            return current.expiresAt.timeIntervalSinceNow > 0 ? current.accessToken : nil
        }
    }

    private func proxyURL(path: String, method: String = "GET") -> URL? {
        var components = URLComponents(string: AppConfig.traktProxyURL)
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "method", value: method)
        ]
        return components?.url
    }

    private func proxyHeaders(userToken: String? = nil) -> [String: String] {
        var headers = [
            "apikey": AppConfig.supabaseAnonKey,
            "Authorization": "Bearer \(AppConfig.supabaseAnonKey)"
        ]
        if let userToken {
            headers["x-user-token"] = userToken
        }
        return headers
    }
}

private extension TraktToken {
    var asCloudToken: CloudTraktToken {
        CloudTraktToken(
            accessToken: accessToken,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            expiresAt: Int64(expiresAt.timeIntervalSince1970)
        )
    }
}
