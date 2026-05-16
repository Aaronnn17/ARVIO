import Foundation

enum MediaKind: String {
    case movie = "Movie"
    case series = "TV Series"

    var tmdbPath: String {
        switch self {
        case .movie: return "movie"
        case .series: return "tv"
        }
    }

    var stremioType: String {
        switch self {
        case .movie: return "movie"
        case .series: return "series"
        }
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let tmdbId: Int?
    let title: String
    let subtitle: String
    let year: String
    let duration: String
    let rating: String
    let kind: MediaKind
    let progress: Double
    let palette: [String]
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    let positionSeconds: Int?
    let durationSeconds: Int?

    init(
        id: String = UUID().uuidString,
        tmdbId: Int? = nil,
        title: String,
        subtitle: String,
        year: String,
        duration: String,
        rating: String,
        kind: MediaKind,
        progress: Double,
        palette: [String],
        posterPath: String? = nil,
        backdropPath: String? = nil,
        overview: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        positionSeconds: Int? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.tmdbId = tmdbId
        self.title = title
        self.subtitle = subtitle
        self.year = year
        self.duration = duration
        self.rating = rating
        self.kind = kind
        self.progress = progress
        self.palette = palette
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }

    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(posterPath)")
    }
}

