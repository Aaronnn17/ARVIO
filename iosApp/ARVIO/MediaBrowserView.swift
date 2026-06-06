import SwiftUI

private struct MediaBrowserSection: Identifiable {
    let id: String
    let title: String
    let query: [String: String]
}

struct MediaBrowserView: View {
    @EnvironmentObject private var appState: AppState
    let kind: MediaKind
    @State private var sections: [String: [MediaItem]] = [:]
    @State private var isLoading = false
    @State private var selectedFilter = "Featured"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                filterStrip

                if let hero = heroItem {
                    HeroSection(item: hero)
                }

                if isLoading && sections.isEmpty {
                    EmptyStatePanel(title: "Loading \(title)", message: "Fetching the same discovery rows used by Android.")
                }

                ForEach(visibleSections) { section in
                    if let items = sections[section.id], !items.isEmpty {
                        MediaRail(title: section.title, items: items)
                    }
                }

                if !isLoading && sections.values.allSatisfy(\.isEmpty) {
                    EmptyStatePanel(title: "No \(title.lowercased()) found", message: "Refresh or check your TMDB configuration.")
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .refreshable {
            await loadSections(force: true)
        }
        .task(id: kind.rawValue) {
            await appState.tmdb.loadHome()
            await loadSections(force: false)
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadSections(force: false) }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .tint(ArvioTheme.gold)
            }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filterNames, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(selectedFilter == filter ? Color.black : ArvioTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedFilter == filter ? ArvioTheme.gold : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedFilter == filter ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var title: String {
        kind == .movie ? "Movies" : "Series"
    }

    private var subtitle: String {
        kind == .movie ? "Discover films by popularity, rating, genre, and language." : "Browse shows by popularity, airing status, genre, and language."
    }

    private var heroItem: MediaItem? {
        if let featured = sections[visibleSections.first?.id ?? ""]?.first {
            return featured
        }
        return kind == .movie ? appState.tmdb.trendingMovies.first : appState.tmdb.trendingSeries.first
    }

    private var filterNames: [String] {
        ["Featured", "Action", "Comedy", "Horror", "Sci-Fi", "Anime", "Korean", "Japanese", "Hindi"]
    }

    private var visibleSections: [MediaBrowserSection] {
        let base = allSections
        guard selectedFilter != "Featured" else { return base }
        return base.filter { $0.id.hasPrefix(selectedFilter.lowercased()) }
    }

    private var allSections: [MediaBrowserSection] {
        let featured = kind == .movie ? movieFeaturedSections : seriesFeaturedSections
        return featured + genreSections
    }

    private var movieFeaturedSections: [MediaBrowserSection] {
        [
            MediaBrowserSection(id: "featured-trending", title: "Trending Movies", query: ["sort_by": "popularity.desc", "vote_count.gte": "80"]),
            MediaBrowserSection(id: "featured-top-rated", title: "Top Rated Movies", query: ["sort_by": "vote_average.desc", "vote_count.gte": "600"]),
            MediaBrowserSection(id: "featured-new", title: "Recently Released", query: ["sort_by": "primary_release_date.desc", "vote_count.gte": "25", "with_release_type": "2|3"])
        ]
    }

    private var seriesFeaturedSections: [MediaBrowserSection] {
        [
            MediaBrowserSection(id: "featured-trending", title: "Trending Series", query: ["sort_by": "popularity.desc", "vote_count.gte": "80"]),
            MediaBrowserSection(id: "featured-top-rated", title: "Top Rated Series", query: ["sort_by": "vote_average.desc", "vote_count.gte": "300"]),
            MediaBrowserSection(id: "featured-airing", title: "Airing Now", query: ["sort_by": "first_air_date.desc", "vote_count.gte": "20", "air_date.gte": recentDateString])
        ]
    }

    private var genreSections: [MediaBrowserSection] {
        [
            MediaBrowserSection(id: "action-main", title: "Action", query: genreQuery(movie: "28", series: "10759")),
            MediaBrowserSection(id: "comedy-main", title: "Comedy", query: genreQuery(movie: "35", series: "35")),
            MediaBrowserSection(id: "horror-main", title: "Horror & Mystery", query: genreQuery(movie: "27", series: "9648")),
            MediaBrowserSection(id: "sci-fi-main", title: "Sci-Fi & Fantasy", query: genreQuery(movie: "878", series: "10765")),
            MediaBrowserSection(id: "anime-main", title: "Anime", query: originQuery(country: "JP", genre: "16")),
            MediaBrowserSection(id: "korean-main", title: "Korean", query: originQuery(country: "KR")),
            MediaBrowserSection(id: "japanese-main", title: "Japanese", query: originQuery(country: "JP")),
            MediaBrowserSection(id: "hindi-main", title: "Hindi", query: originQuery(country: "IN"))
        ]
    }

    private func genreQuery(movie: String, series: String) -> [String: String] {
        [
            "sort_by": "popularity.desc",
            "include_adult": "false",
            "vote_count.gte": "35",
            "with_genres": kind == .movie ? movie : series
        ]
    }

    private func originQuery(country: String, genre: String? = nil) -> [String: String] {
        var query = [
            "sort_by": "popularity.desc",
            "include_adult": "false",
            "vote_count.gte": "20",
            "with_origin_country": country
        ]
        if let genre {
            query["with_genres"] = genre
        }
        return query
    }

    private var recentDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return formatter.string(from: date)
    }

    private func loadSections(force: Bool) async {
        let targets = visibleSections
        if !force && targets.allSatisfy({ sections[$0.id]?.isEmpty == false }) {
            return
        }
        isLoading = true
        defer { isLoading = false }

        for section in targets {
            if !force, sections[section.id]?.isEmpty == false {
                continue
            }
            sections[section.id] = (try? await appState.tmdb.discoverItems(kind: kind, query: section.query, limit: 24)) ?? []
        }
    }
}
