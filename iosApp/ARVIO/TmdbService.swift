import Foundation

struct TmdbListResponse: Decodable {
    let results: [TmdbMedia]
}

struct TmdbMedia: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case mediaType = "media_type"
    }

    func asMediaItem(defaultKind: MediaKind? = nil) -> MediaItem? {
        let resolvedKind: MediaKind
        if let defaultKind {
            resolvedKind = defaultKind
        } else if mediaType == "movie" {
            resolvedKind = .movie
        } else if mediaType == "tv" {
            resolvedKind = .series
        } else {
            return nil
        }

        let resolvedTitle = title ?? name ?? "Untitled"
        let date = releaseDate ?? firstAirDate ?? ""
        let year = String(date.prefix(4))
        let rating = voteAverage.map { String(format: "%.1f", $0) } ?? ""
        return MediaItem(
            id: "\(resolvedKind.tmdbPath)-\(id)",
            tmdbId: id,
            title: resolvedTitle,
            subtitle: resolvedKind.rawValue,
            year: year,
            duration: "",
            rating: rating,
            kind: resolvedKind,
            progress: 0,
            palette: ["#10202a", "#071017"],
            posterPath: posterPath,
            backdropPath: backdropPath,
            overview: overview
        )
    }
}

struct TmdbGenre: Decodable, Hashable {
    let id: Int
    let name: String
}

struct TmdbDetails: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let runtime: Int?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let episodeRunTime: [Int]?
    let genres: [TmdbGenre]?
    let seasons: [TmdbSeason]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case runtime
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case genres
        case seasons
    }
}

struct TmdbSeason: Decodable, Identifiable, Hashable {
    let id: Int
    let seasonNumber: Int
    let episodeCount: Int?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case name
    }
}

struct TmdbExternalIds: Decodable {
    let imdbId: String?
    let tvdbId: Int?

    enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
        case tvdbId = "tvdb_id"
    }
}

@MainActor
final class TmdbService: ObservableObject {
    @Published private(set) var trendingMovies: [MediaItem] = []
    @Published private(set) var trendingSeries: [MediaItem] = []
    @Published private(set) var searchResults: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client = JSONClient()

    func loadHome() async {
        guard trendingMovies.isEmpty && trendingSeries.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let movies: TmdbListResponse = tmdb(path: "/trending/movie/day", query: ["language": "en-US"])
            async let series: TmdbListResponse = tmdb(path: "/trending/tv/day", query: ["language": "en-US"])
            trendingMovies = try await movies.results.compactMap { $0.asMediaItem(defaultKind: .movie) }
            trendingSeries = try await series.results.compactMap { $0.asMediaItem(defaultKind: .series) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: TmdbListResponse = try await tmdb(path: "/search/multi", query: ["query": trimmed, "language": "en-US"])
            searchResults = response.results.compactMap { $0.asMediaItem() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func details(for item: MediaItem) async throws -> TmdbDetails {
        guard let tmdbId = item.tmdbId else {
            throw ArvioError.requestFailed("Missing TMDB id")
        }
        return try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)", query: ["language": "en-US"])
    }

    func externalIds(for item: MediaItem) async throws -> TmdbExternalIds {
        guard let tmdbId = item.tmdbId else {
            throw ArvioError.requestFailed("Missing TMDB id")
        }
        return try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)/external_ids", query: [:])
    }

    func recommendations(for item: MediaItem) async throws -> [MediaItem] {
        guard let tmdbId = item.tmdbId else { return [] }
        let response: TmdbListResponse = try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)/recommendations", query: ["language": "en-US"])
        return response.results.compactMap { $0.asMediaItem(defaultKind: item.kind) }
    }

    private func tmdb<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        guard AppConfig.isCloudConfigured else {
            throw ArvioError.missingConfiguration("Supabase")
        }
        var components = URLComponents(string: AppConfig.tmdbProxyURL)
        components?.queryItems = [URLQueryItem(name: "path", value: path)] + query.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components?.url else {
            throw ArvioError.invalidURL(path)
        }
        return try await client.request(
            url,
            headers: [
                "apikey": AppConfig.supabaseAnonKey,
                "Authorization": "Bearer \(AppConfig.supabaseAnonKey)"
            ]
        )
    }
}
