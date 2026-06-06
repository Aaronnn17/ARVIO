import Foundation

struct TmdbListResponse: Decodable {
    let results: [TmdbMedia]
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case results
        case totalPages = "total_pages"
    }
}

struct TmdbFindResponse: Decodable {
    let movieResults: [TmdbMedia]?
    let tvResults: [TmdbMedia]?

    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

private struct TmdbTraktListItem: Decodable {
    let type: String
    let movie: TmdbTraktMedia?
    let show: TmdbTraktMedia?
}

private struct TmdbTraktMedia: Decodable {
    let title: String?
    let year: Int?
    let ids: TmdbTraktIds?
}

private struct TmdbTraktIds: Decodable {
    let tmdb: Int?
    let imdb: String?
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
    let voteCount: Int?
    let mediaType: String?
    let popularity: Double?
    let profilePath: String?
    let knownFor: [TmdbMedia]?

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
        case voteCount = "vote_count"
        case mediaType = "media_type"
        case popularity
        case profilePath = "profile_path"
        case knownFor = "known_for"
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

struct TmdbPersonKnownForRow: Identifiable, Hashable {
    let id: String
    let personId: Int
    let name: String
    let profilePath: String?
    let items: [MediaItem]

    var profileURL: URL? {
        guard let profilePath else { return nil }
        if profilePath.hasPrefix("http") { return URL(string: profilePath) }
        return URL(string: "https://image.tmdb.org/t/p/w342\(profilePath)")
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
    let belongsToCollection: TmdbCollectionRef?

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
        case belongsToCollection = "belongs_to_collection"
    }

    func asMediaItem(kind: MediaKind) -> MediaItem {
        let resolvedTitle = title ?? name ?? "Untitled"
        let date = releaseDate ?? firstAirDate ?? ""
        let year = String(date.prefix(4))
        let rating = voteAverage.map { String(format: "%.1f", $0) } ?? ""
        let runtimeMinutes = runtime ?? episodeRunTime?.first ?? 0
        let duration: String
        if runtimeMinutes > 0 {
            duration = runtimeMinutes >= 60 ? "\(runtimeMinutes / 60)h \(runtimeMinutes % 60)m" : "\(runtimeMinutes)m"
        } else {
            duration = ""
        }
        return MediaItem(
            id: "\(kind.tmdbPath)-\(id)",
            tmdbId: id,
            title: resolvedTitle,
            subtitle: kind.rawValue,
            year: year,
            duration: duration,
            rating: rating,
            kind: kind,
            progress: 0,
            palette: ["#10202a", "#071017"],
            posterPath: posterPath,
            backdropPath: backdropPath,
            overview: overview,
            durationSeconds: runtimeMinutes > 0 ? runtimeMinutes * 60 : nil
        )
    }
}

struct TmdbCollectionRef: Decodable, Hashable {
    let id: Int
    let name: String?
    let posterPath: String?
    let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
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

struct TmdbReviewsResponse: Decodable {
    let results: [TmdbReview]
}

struct TmdbReview: Decodable, Identifiable, Hashable {
    let id: String
    let author: String
    let authorDetails: TmdbAuthorDetails?
    let content: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case authorDetails = "author_details"
        case content
        case createdAt = "created_at"
    }

    var displayAuthor: String {
        authorDetails?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            author.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            "TMDB user"
    }

    var ratingText: String? {
        guard let rating = authorDetails?.rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }
}

struct TmdbAuthorDetails: Decodable, Hashable {
    let name: String?
    let username: String?
    let avatarPath: String?
    let rating: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case username
        case avatarPath = "avatar_path"
        case rating
    }

    var avatarURL: URL? {
        guard let avatarPath = avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines), !avatarPath.isEmpty else {
            return nil
        }
        if avatarPath.hasPrefix("/http") {
            return URL(string: String(avatarPath.dropFirst()))
        }
        return URL(string: "https://image.tmdb.org/t/p/w185\(avatarPath)")
    }
}

struct TmdbCombinedCredits: Decodable {
    let cast: [TmdbMedia]
}

struct TmdbPersonDetails: Decodable, Identifiable {
    let id: Int
    let name: String
    let biography: String?
    let placeOfBirth: String?
    let birthday: String?
    let profilePath: String?
    let combinedCredits: TmdbCombinedCredits?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case biography
        case placeOfBirth = "place_of_birth"
        case birthday
        case profilePath = "profile_path"
        case combinedCredits = "combined_credits"
    }

    var imageURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(profilePath)")
    }

    var knownFor: [MediaItem] {
        Array((combinedCredits?.cast ?? [])
            .filter { $0.posterPath != nil && ($0.mediaType == "movie" || $0.mediaType == "tv") }
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
            .compactMap { $0.asMediaItem() }
            .prefix(20))
    }
}

private struct TmdbCollectionResponse: Decodable {
    let name: String?
    let parts: [TmdbMedia]
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
            searchResults = try await searchItems(trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchItems(_ query: String) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let response: TmdbListResponse = try await tmdb(
            path: "/search/multi",
            query: ["query": trimmed, "language": "en-US", "include_adult": "false"]
        )
        return response.results
            .compactMap { $0.asMediaItem() }
            .sortedForSearch(query: trimmed)
            .uniquedById()
    }

    func searchPeopleKnownFor(_ query: String, maxPeople: Int = 3) async throws -> [TmdbPersonKnownForRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, maxPeople > 0 else { return [] }
        let response: TmdbListResponse = try await tmdb(
            path: "/search/multi",
            query: ["query": trimmed, "language": "en-US", "include_adult": "false"]
        )
        let people = response.results
            .filter { $0.mediaType == "person" && !($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                ($0.popularity ?? 0) == ($1.popularity ?? 0)
                    ? ($0.name ?? "") < ($1.name ?? "")
                    : ($0.popularity ?? 0) > ($1.popularity ?? 0)
            }
            .prefix(maxPeople)

        var rows: [TmdbPersonKnownForRow] = []
        for person in people {
            var knownFor = (person.knownFor ?? [])
                .compactMap { $0.asMediaItem() }
                .uniquedById()

            if knownFor.isEmpty {
                let details = try? await personDetails(personId: person.id)
                knownFor = (details?.combinedCredits?.cast ?? [])
                    .compactMap { $0.asMediaItem() }
                    .sorted { ($0.rating) > ($1.rating) }
                    .uniquedById()
            }

            guard !knownFor.isEmpty else { continue }
            rows.append(
                TmdbPersonKnownForRow(
                    id: "person-\(person.id)",
                    personId: person.id,
                    name: person.name ?? "Person",
                    profilePath: person.profilePath,
                    items: Array(knownFor.prefix(20))
                )
            )
        }
        return rows
    }

    func similarItems(to query: String, preferredKind: MediaKind?) async throws -> [MediaItem] {
        let candidates = try await searchItems(query)
        guard let seed = candidates.first(where: { preferredKind == nil || $0.kind == preferredKind }) ?? candidates.first else {
            return []
        }
        return try await recommendations(for: seed)
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

    func reviews(for item: MediaItem) async throws -> [TmdbReview] {
        guard let tmdbId = item.tmdbId else { return [] }
        let response: TmdbReviewsResponse = try await tmdb(path: "/\(item.kind.tmdbPath)/\(tmdbId)/reviews", query: ["language": "en-US"])
        return Array(response.results.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(12))
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

    func items(for refs: [(MediaKind, Int)], limit: Int) async throws -> [MediaItem] {
        var output: [MediaItem] = []
        for (kind, tmdbId) in refs.prefix(limit) {
            if let item = try? await itemDetails(tmdbId: tmdbId, kind: kind) {
                output.append(item)
            }
        }
        return output
    }

    func discoverItems(kind: MediaKind, query: [String: String], limit: Int) async throws -> [MediaItem] {
        guard limit > 0 else { return [] }
        var page = 1
        var totalPages = 1
        var output: [MediaItem] = []
        while output.count < limit && page <= totalPages {
            var merged = query
            merged["language"] = merged["language"] ?? "en-US"
            merged["page"] = "\(page)"
            let response: TmdbListResponse = try await tmdb(path: "/discover/\(kind.tmdbPath)", query: merged)
            output.append(contentsOf: response.results.compactMap { $0.asMediaItem(defaultKind: kind) })
            totalPages = max(response.totalPages ?? 1, 1)
            if response.results.isEmpty { break }
            page += 1
        }
        return Array(output.prefix(limit))
    }

    func collectionItems(collectionId: Int, limit: Int) async throws -> [MediaItem] {
        guard limit > 0 else { return [] }
        let response: TmdbCollectionResponse = try await tmdb(path: "/collection/\(collectionId)", query: ["language": "en-US"])
        let sorted = response.parts.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
        return Array(sorted.compactMap { $0.asMediaItem(defaultKind: .movie) }.prefix(limit))
    }

    func listItems(from rawURL: String?, fallbackKind: MediaKind) async throws -> [MediaItem] {
        guard let normalized = normalizeCatalogURL(rawURL) else { return [] }
        if isTraktURL(normalized) {
            return try await traktListItems(from: normalized, fallbackKind: fallbackKind)
        }
        if isMdblistURL(normalized) {
            let jsonURL = normalized.hasSuffix("/json") ? normalized : "\(normalized)/json"
            if let items = try? await directListItems(from: jsonURL, fallbackKind: fallbackKind),
               !items.isEmpty {
                return items
            }
            if let html = try? await fetchText(from: normalized),
               let traktURL = firstTraktListURL(in: html) {
                return try await traktListItems(from: traktURL, fallbackKind: fallbackKind)
            }
        }
        if let items = try await directListItems(from: normalized, fallbackKind: fallbackKind), !items.isEmpty {
            return items
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

    func personDetails(personId: Int) async throws -> TmdbPersonDetails {
        try await tmdb(
            path: "/person/\(personId)",
            query: ["language": "en-US", "append_to_response": "combined_credits"]
        )
    }

    private func directListItems(from rawURL: String, fallbackKind: MediaKind) async throws -> [MediaItem]? {
        guard let url = URL(string: rawURL) else { return nil }
        let (data, response) = try await URLSession.shared.data(for: catalogRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return try await resolveExternalList(decoded, fallbackKind: fallbackKind)
        }
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = decoded["items"] as? [[String: Any]] ?? decoded["results"] as? [[String: Any]] ?? decoded["metas"] as? [[String: Any]] {
            return try await resolveExternalList(items, fallbackKind: fallbackKind)
        }
        return nil
    }

    private func resolveExternalList(_ values: [[String: Any]], fallbackKind: MediaKind) async throws -> [MediaItem] {
        var resolved: [MediaItem] = []
        for value in values.prefix(40) {
            let nestedMovie = value["movie"] as? [String: Any]
            let nestedShow = value["show"] as? [String: Any]
            let mediaValue = nestedMovie ?? nestedShow ?? value
            let ids = mediaValue["ids"] as? [String: Any]
            if let tmdb = intValue(ids?["tmdb"]) ?? intValue(mediaValue["tmdb"]) ?? intValue(mediaValue["tmdb_id"]) ?? intValue(mediaValue["tmdbId"]) ?? intValue(mediaValue["id"]) {
                let defaultKind: MediaKind = nestedShow != nil ? .series : (nestedMovie != nil ? .movie : fallbackKind)
                let kind = externalKind(type: (value["type"] as? String) ?? (mediaValue["type"] as? String), fallback: defaultKind)
                if let item = try? await itemDetails(tmdbId: tmdb, kind: kind) {
                    resolved.append(item)
                } else {
                    let item = TmdbMedia(
                        id: tmdb,
                        title: mediaValue["title"] as? String,
                        name: mediaValue["name"] as? String,
                        overview: mediaValue["overview"] as? String,
                        releaseDate: mediaValue["release_date"] as? String,
                        firstAirDate: mediaValue["first_air_date"] as? String,
                        posterPath: mediaValue["poster_path"] as? String,
                        backdropPath: mediaValue["backdrop_path"] as? String,
                        voteAverage: mediaValue["vote_average"] as? Double,
                        voteCount: intValue(mediaValue["vote_count"]),
                        mediaType: kind == .movie ? "movie" : "tv",
                        popularity: mediaValue["popularity"] as? Double,
                        profilePath: nil,
                        knownFor: nil
                    ).asMediaItem(defaultKind: kind)
                    if let item { resolved.append(item) }
                }
            } else if let imdb = ids?["imdb"] as? String ?? mediaValue["imdb"] as? String ?? mediaValue["imdb_id"] as? String {
                let find: TmdbFindResponse = try await tmdb(path: "/find/\(imdb)", query: ["external_source": "imdb_id"])
                if let movie = find.movieResults?.first?.asMediaItem(defaultKind: .movie) {
                    resolved.append(movie)
                } else if let show = find.tvResults?.first?.asMediaItem(defaultKind: .series) {
                    resolved.append(show)
                }
            }
        }
        return resolved.uniquedById()
    }

    private func traktListItems(from rawURL: String, fallbackKind: MediaKind) async throws -> [MediaItem] {
        guard let parsedPath = parseTraktList(rawURL) else { return [] }
        var rows: [TmdbTraktListItem] = []
        for type in ["movies", "shows"] {
            guard let url = traktProxyURL(path: "\(parsedPath)/items/\(type)?extended=full&page=1&limit=100") else { continue }
            let chunk: [TmdbTraktListItem] = (try? await client.request(url, headers: proxyHeaders())) ?? []
            rows.append(contentsOf: chunk)
        }
        let values = rows.map { row -> [String: Any] in
            let media = row.movie ?? row.show
            var ids: [String: Any] = [:]
            if let tmdb = media?.ids?.tmdb { ids["tmdb"] = tmdb }
            if let imdb = media?.ids?.imdb { ids["imdb"] = imdb }
            var entry: [String: Any] = [
                "type": row.show == nil ? "movie" : "show",
                "ids": ids
            ]
            if let title = media?.title { entry["title"] = title }
            if let year = media?.year { entry["year"] = year }
            return entry
        }
        return try await resolveExternalList(values, fallbackKind: fallbackKind)
    }

    func itemDetails(tmdbId: Int, kind: MediaKind) async throws -> MediaItem {
        let details: TmdbDetails = try await tmdb(path: "/\(kind.tmdbPath)/\(tmdbId)", query: ["language": "en-US"])
        return details.asMediaItem(kind: kind)
    }

    private func externalKind(type: String?, fallback: MediaKind) -> MediaKind {
        let value = type?.lowercased() ?? ""
        if value.contains("tv") || value.contains("show") || value.contains("series") { return .series }
        if value.contains("movie") { return .movie }
        return fallback
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func normalizeCatalogURL(_ rawURL: String?) -> String? {
        var value = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.hasPrefix("mdblist:") { value = String(value.dropFirst("mdblist:".count)) }
        if value.hasPrefix("mdblist_trakt:") { value = String(value.dropFirst("mdblist_trakt:".count)) }
        if value.hasPrefix("trakt_url:") { value = String(value.dropFirst("trakt_url:".count)) }
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func isMdblistURL(_ value: String) -> Bool {
        URL(string: value)?.host?.lowercased().contains("mdblist.com") == true
    }

    private func isTraktURL(_ value: String) -> Bool {
        URL(string: value)?.host?.lowercased().contains("trakt.tv") == true
    }

    private func firstTraktListURL(in html: String) -> String? {
        let pattern = #"https?://(?:www\.)?trakt\.tv/users/[^"'\s<]+/lists/[^"'\s<]+"#
        return html.range(of: pattern, options: [.regularExpression, .caseInsensitive]).map { String(html[$0]) }
    }

    private func fetchText(from rawURL: String) async throws -> String {
        guard let url = URL(string: rawURL) else { throw ArvioError.invalidURL(rawURL) }
        let (data, response) = try await URLSession.shared.data(for: catalogRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Catalog request failed")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func catalogRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPad; ARVIO)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html,*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private func parseTraktList(_ rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let host = url.host?.lowercased(),
              host.contains("trakt.tv") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.count >= 4, parts[0] == "users", parts[2] == "lists" {
            return "/users/\(parts[1])/lists/\(parts[3])"
        }
        if parts.count >= 2, parts[0] == "lists" {
            return "/lists/\(parts[1])"
        }
        return nil
    }

    private func traktProxyURL(path: String, method: String = "GET") -> URL? {
        var components = URLComponents(string: AppConfig.traktProxyURL)
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "method", value: method)
        ]
        return components?.url
    }

    private func proxyHeaders() -> [String: String] {
        [
            "apikey": AppConfig.supabaseAnonKey,
            "Authorization": "Bearer \(AppConfig.supabaseAnonKey)"
        ]
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

private extension Array where Element == MediaItem {
    func uniquedById() -> [MediaItem] {
        var seen = Set<String>()
        return filter { item in
            let key = "\(item.kind.tmdbPath)-\(item.tmdbId ?? -1)-\(item.title)"
            return seen.insert(key).inserted
        }
    }

    func sortedForSearch(query: String) -> [MediaItem] {
        let normalizedQuery = query.normalizedForSearchRanking
        return sorted { left, right in
            let leftRank = left.searchRank(against: normalizedQuery)
            let rightRank = right.searchRank(against: normalizedQuery)
            if leftRank != rightRank { return leftRank < rightRank }

            let leftRating = Double(left.rating) ?? 0
            let rightRating = Double(right.rating) ?? 0
            if leftRating != rightRating { return leftRating > rightRating }

            let leftYear = Int(left.year) ?? 0
            let rightYear = Int(right.year) ?? 0
            if leftYear != rightYear { return leftYear > rightYear }

            return left.title < right.title
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedForSearchRanking: String {
        lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MediaItem {
    func searchRank(against normalizedQuery: String) -> Int {
        let title = title.normalizedForSearchRanking
        if title == normalizedQuery { return 0 }
        if title.hasPrefix(normalizedQuery) { return 1 }
        if title.contains(normalizedQuery) { return 2 }
        let queryWords = normalizedQuery.split(separator: " ")
        if !queryWords.isEmpty && queryWords.allSatisfy({ title.contains($0) }) { return 2 }
        return 3
    }
}
