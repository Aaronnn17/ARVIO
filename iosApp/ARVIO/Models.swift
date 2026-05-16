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
        overview: String? = nil
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

let featuredItems: [MediaItem] = [
    MediaItem(title: "Echoes of Dawn", subtitle: "S1 • E6 • New episode", year: "2026", duration: "45m", rating: "8.7", kind: .series, progress: 0.72, palette: ["#d99b4f", "#4b2b19"]),
    MediaItem(title: "Neon Paradox", subtitle: "Cyber noir thriller", year: "2025", duration: "2h 10m", rating: "8.2", kind: .movie, progress: 0.0, palette: ["#2276ff", "#141b3c"]),
    MediaItem(title: "Beyond the Wilds", subtitle: "S2 • E3", year: "2026", duration: "50m", rating: "8.0", kind: .series, progress: 0.28, palette: ["#9cbf6a", "#1d2d21"]),
    MediaItem(title: "The Architect", subtitle: "Premium action cinema", year: "2025", duration: "1h 58m", rating: "7.9", kind: .movie, progress: 0.0, palette: ["#d64a36", "#241112"])
]

let continueWatchingItems: [MediaItem] = [
    MediaItem(title: "Night Watch", subtitle: "Resume episode", year: "2026", duration: "47m left", rating: "8.4", kind: .series, progress: 0.41, palette: ["#315f8d", "#081826"]),
    MediaItem(title: "Deep Current", subtitle: "S1 • E4", year: "2026", duration: "19m left", rating: "8.1", kind: .series, progress: 0.64, palette: ["#1a9ec0", "#06242c"]),
    MediaItem(title: "The Long Orbit", subtitle: "Continue movie", year: "2025", duration: "54m left", rating: "7.8", kind: .movie, progress: 0.52, palette: ["#7961c8", "#18152d"])
]
