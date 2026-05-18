import Foundation

struct TmdbListResponse: Decodable {
    let results: [TmdbMedia]
}

struct TmdbFindResponse: Decodable {
    let movieResults: [TmdbMedia]?
    let tvResults: [TmdbMedia]?

    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
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

struct TmdbEpisodeListResponse: Decodable {
    let episodes: [TmdbEpisode]
}

struct TmdbEpisode: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String?
    let stillPath: String?
    let voteAverage: Double?
    let runtime: Int?
    let airDate: String?
    let episodeNumber: Int
    let seasonNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case stillPath = "still_path"
        case voteAverage = "vote_average"
        case runtime
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
    }
}

struct TmdbVideoResponse: Decodable {
    let results: [TmdbVideo]
}

struct TmdbVideo: Decodable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
}

struct TmdbCastResponse: Decodable {
    let cast: [TmdbCastMember]
}

struct TmdbCastMember: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case character
        case profilePath = "profile_path"
    }

    var imageURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
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

    func catalogItems(for config: CatalogConfig) async throws -> [MediaItem] {
        let id = config.id.lowercased()
        let endpoint: (String, MediaKind)
        switch id {
        case "trending_movies", "movie_trending", "movies_trending":
            endpoint = ("/trending/movie/day", .movie)
        case "trending_series", "trending_tv", "series_trending", "tv_trending":
            endpoint = ("/trending/tv/day", .series)
        case "popular_movies", "movie_popular", "movies_popular":
            endpoint = ("/movie/popular", .movie)
        case "popular_series", "popular_tv", "series_popular", "tv_popular":
            endpoint = ("/tv/popular", .series)
        case "top_rated_movies", "movie_top_rated":
            endpoint = ("/movie/top_rated", .movie)
        case "top_rated_series", "tv_top_rated", "series_top_rated":
            endpoint = ("/tv/top_rated", .series)
        case "now_playing_movies", "movie_now_playing":
            endpoint = ("/movie/now_playing", .movie)
        case "airing_today_series", "tv_airing_today", "series_airing_today":
            endpoint = ("/tv/airing_today", .series)
        default:
            if id.contains("series") || id.contains("tv") {
                endpoint = ("/tv/popular", .series)
            } else {
                endpoint = ("/movie/popular", .movie)
            }
        }
        let response: TmdbListResponse = try await tmdb(path: endpoint.0, query: ["language": "en-US"])
        return response.results.compactMap { $0.asMediaItem(defaultKind: endpoint.1) }
    }

    func listItems(from rawURL: String?, fallbackKind: MediaKind) async throws -> [MediaItem] {
        guard let rawURL, let url = URL(string: rawURL) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return try await resolveExternalList(decoded, fallbackKind: fallbackKind)
        }
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = decoded["items"] as? [[String: Any]] ?? decoded["results"] as? [[String: Any]] {
            return try await resolveExternalList(items, fallbackKind: fallbackKind)
        }
        return []
    }

    func seasonEpisodes(for item: MediaItem, season: Int) async throws -> [TmdbEpisode] {
        guard let tmdbId = item.tmdbId else { return [] }
        let response: TmdbEpisodeListResponse = try await tmdb(path: "/tv/\(tmdbId)/season/\(season)", query: ["language": "en-US"])
        return response.episodes
    }

    func trailerURL(for item: MediaItem) async throws -> URL? {
        guard let tmdbId = item.tmdbId else { return nil }
        let response: TmdbVideoResponse = try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)/videos", query: ["language": "en-US"])
        let trailer = response.results.first { $0.site == "YouTube" && $0.type == "Trailer" } ??
            response.results.first { $0.site == "YouTube" }
        return trailer.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
    }

    func cast(for item: MediaItem) async throws -> [TmdbCastMember] {
        guard let tmdbId = item.tmdbId else { return [] }
        let response: TmdbCastResponse = try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)/credits", query: ["language": "en-US"])
        return Array(response.cast.prefix(16))
    }

    private func resolveExternalList(_ values: [[String: Any]], fallbackKind: MediaKind) async throws -> [MediaItem] {
        var resolved: [MediaItem] = []
        for value in values.prefix(40) {
            if let tmdb = value["tmdb"] as? Int ?? value["tmdb_id"] as? Int ?? value["id"] as? Int {
                let kind = ((value["type"] as? String) ?? "").lowercased().contains("show") ? MediaKind.series : fallbackKind
                let item = TmdbMedia(id: tmdb, title: value["title"] as? String, name: value["name"] as? String, overview: nil, releaseDate: nil, firstAirDate: nil, posterPath: nil, backdropPath: nil, voteAverage: nil, mediaType: kind == .movie ? "movie" : "tv").asMediaItem(defaultKind: kind)
                if let item { resolved.append(item) }
            } else if let imdb = value["imdb"] as? String ?? value["imdb_id"] as? String {
                let find: TmdbFindResponse = try await tmdb(path: "/find/\(imdb)", query: ["external_source": "imdb_id"])
                if let movie = find.movieResults?.first?.asMediaItem(defaultKind: .movie) {
                    resolved.append(movie)
                } else if let show = find.tvResults?.first?.asMediaItem(defaultKind: .series) {
                    resolved.append(show)
                }
            }
        }
        return resolved
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
