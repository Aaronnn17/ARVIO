import SwiftUI

private enum SearchDiscoverFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case shows
    case anime
    case action
    case comedy
    case horror
    case sciFi
    case japanese
    case korean
    case hindi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .shows: return "TV Shows"
        case .anime: return "Anime"
        case .action: return "Action"
        case .comedy: return "Comedy"
        case .horror: return "Horror"
        case .sciFi: return "Sci-Fi"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .hindi: return "Hindi"
        }
    }

    var includesMovies: Bool {
        self != .shows && self != .anime
    }

    var includesSeries: Bool {
        self != .movies
    }

    func query(for kind: MediaKind) -> [String: String] {
        var query = [
            "sort_by": "popularity.desc",
            "include_adult": "false",
            "vote_count.gte": "35"
        ]
        switch self {
        case .all, .movies, .shows:
            break
        case .anime:
            query["with_genres"] = "16"
            query["with_origin_country"] = "JP"
        case .action:
            query["with_genres"] = kind == .movie ? "28" : "10759"
        case .comedy:
            query["with_genres"] = "35"
        case .horror:
            query["with_genres"] = kind == .movie ? "27" : "9648"
        case .sciFi:
            query["with_genres"] = kind == .movie ? "878" : "10765"
        case .japanese:
            query["with_origin_country"] = "JP"
        case .korean:
            query["with_origin_country"] = "KR"
        case .hindi:
            query["with_origin_country"] = "IN"
        }
        return query
    }
}

private enum SmartSearchScope: Equatable {
    case all
    case movies
    case shows
    case anime

    var preferredKind: MediaKind? {
        switch self {
        case .all: return nil
        case .movies: return .movie
        case .shows, .anime: return .series
        }
    }
}

private enum SmartSearchSort: Equatable {
    case popular
    case topRated
    case newest
}

private struct SmartSearchRequest {
    let interpretation: String
    let scope: SmartSearchScope
    let genreId: String?
    let genreName: String?
    let sort: SmartSearchSort
    let minVotes: String?
    let limit: Int?
    let similarTo: String?
}

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var selectedFilter: SearchDiscoverFilter = .all
    @State private var discoverMovies: [MediaItem] = []
    @State private var discoverSeries: [MediaItem] = []
    @State private var isDiscoverLoading = false
    @State private var personRows: [TmdbPersonKnownForRow] = []
    @State private var isSmartSearch = false
    @State private var smartInterpretation = ""
    @State private var smartResults: [MediaItem] = []
    @State private var isSmartLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Search")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)

                TextField("Search movies, shows and episodes", text: $query)
                    .textInputAutocapitalization(.never)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .onSubmit {
                        Task { await performSearch(query) }
                    }
                    .onChange(of: query) { _, value in
                        Task { await performSearch(value) }
                    }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filterStrip
                    discoverContent
                } else {
                    searchContent
                }
            }
            .padding(28)
        }
        .task {
            await appState.tmdb.loadHome()
            await loadDiscover()
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadDiscover() }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchDiscoverFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(selectedFilter == filter ? Color.black : ArvioTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selectedFilter == filter ? ArvioTheme.gold : Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedFilter == filter ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var discoverContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isDiscoverLoading {
                ProgressView()
                    .tint(ArvioTheme.gold)
            }
            if selectedFilter == .all {
                MediaRail(title: "Trending Movies", items: appState.tmdb.trendingMovies)
                MediaRail(title: "Trending TV Shows", items: appState.tmdb.trendingSeries)
            } else {
                if !discoverMovies.isEmpty {
                    MediaRail(title: "\(selectedFilter.label) Movies", items: discoverMovies)
                }
                if !discoverSeries.isEmpty {
                    MediaRail(title: "\(selectedFilter.label) TV Shows", items: discoverSeries)
                }
                if discoverMovies.isEmpty && discoverSeries.isEmpty && !isDiscoverLoading {
                    EmptyStatePanel(title: "No results", message: "Try another filter.")
                }
            }
        }
    }

    private var searchContent: some View {
        let movies = appState.tmdb.searchResults.filter { $0.kind == .movie }
        let series = appState.tmdb.searchResults.filter { $0.kind == .series }
        let personItems = Array(personRows.flatMap(\.items).prefix(24))
        let top = uniqueItems(personItems + Array(interleaved(movies: movies, series: series).prefix(32)))
        return VStack(alignment: .leading, spacing: 20) {
            if appState.tmdb.isLoading || isSmartLoading {
                ProgressView()
                    .tint(ArvioTheme.gold)
            }
            if isSmartSearch {
                if !smartInterpretation.isEmpty {
                    Text(smartInterpretation)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ArvioTheme.gold)
                }
                if !smartResults.isEmpty {
                    MediaRail(title: "Smart Search (\(smartResults.count))", items: smartResults)
                }
                if smartResults.isEmpty && !isSmartLoading {
                    EmptyStatePanel(title: "No results", message: "No titles matched \(smartInterpretation.isEmpty ? query : smartInterpretation).")
                }
            } else {
                ForEach(personRows) { row in
                    MediaRail(title: row.name, items: row.items)
                }
                if !top.isEmpty {
                    MediaRail(title: "Search (\(top.count))", items: top)
                }
                if !movies.isEmpty {
                    MediaRail(title: "Movies (\(movies.count))", items: movies)
                }
                if !series.isEmpty {
                    MediaRail(title: "TV Shows (\(series.count))", items: series)
                }
                if top.isEmpty && personRows.isEmpty && !appState.tmdb.isLoading {
                    EmptyStatePanel(title: "No results", message: "No movies or shows matched \(query).")
                }
            }
        }
    }

    private func performSearch(_ rawQuery: String) async {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            personRows = []
            isSmartSearch = false
            smartInterpretation = ""
            smartResults = []
            isSmartLoading = false
            return
        }

        if let smart = parseSmartSearch(trimmed) {
            isSmartSearch = true
            smartInterpretation = smart.interpretation
            personRows = []
            smartResults = []
            isSmartLoading = true
            defer { isSmartLoading = false }
            smartResults = await loadSmartResults(smart)
            return
        }

        isSmartSearch = false
        smartInterpretation = ""
        smartResults = []
        async let mediaSearch: Void = appState.tmdb.search(trimmed)
        async let peopleSearch: [TmdbPersonKnownForRow] = (try? await appState.tmdb.searchPeopleKnownFor(trimmed)) ?? []
        _ = await mediaSearch
        personRows = await peopleSearch
    }

    private func loadDiscover() async {
        guard selectedFilter != .all else {
            discoverMovies = []
            discoverSeries = []
            return
        }
        isDiscoverLoading = true
        defer { isDiscoverLoading = false }
        async let movies = discover(kind: .movie, include: selectedFilter.includesMovies)
        async let series = discover(kind: .series, include: selectedFilter.includesSeries)
        discoverMovies = await movies
        discoverSeries = await series
    }

    private func discover(kind: MediaKind, include: Bool) async -> [MediaItem] {
        guard include else { return [] }
        return (try? await appState.tmdb.discoverItems(kind: kind, query: selectedFilter.query(for: kind), limit: 24)) ?? []
    }

    private func loadSmartResults(_ request: SmartSearchRequest) async -> [MediaItem] {
        if let similarTo = request.similarTo {
            return (try? await appState.tmdb.similarItems(to: similarTo, preferredKind: request.scope.preferredKind)) ?? []
        }

        let limit = request.limit ?? 48
        switch request.scope {
        case .movies:
            return (try? await appState.tmdb.discoverItems(kind: .movie, query: smartQuery(for: .movie, request: request), limit: limit)) ?? []
        case .shows, .anime:
            return (try? await appState.tmdb.discoverItems(kind: .series, query: smartQuery(for: .series, request: request), limit: limit)) ?? []
        case .all:
            async let movies = appState.tmdb.discoverItems(kind: .movie, query: smartQuery(for: .movie, request: request), limit: limit)
            async let series = appState.tmdb.discoverItems(kind: .series, query: smartQuery(for: .series, request: request), limit: limit)
            let combined = ((try? await movies) ?? []) + ((try? await series) ?? [])
            return Array(uniqueItems(combined).prefix(limit))
        }
    }

    private func smartQuery(for kind: MediaKind, request: SmartSearchRequest) -> [String: String] {
        var output = [
            "include_adult": "false",
            "vote_count.gte": request.minVotes ?? "35"
        ]
        switch request.sort {
        case .popular:
            output["sort_by"] = "popularity.desc"
        case .topRated:
            output["sort_by"] = "vote_average.desc"
            output["vote_count.gte"] = request.minVotes ?? "500"
        case .newest:
            output["sort_by"] = kind == .movie ? "primary_release_date.desc" : "first_air_date.desc"
        }

        if request.scope == .anime {
            output["with_genres"] = "16"
            output["with_keywords"] = "210024"
            output["with_origin_country"] = "JP"
        } else if let genreId = request.genreId {
            output["with_genres"] = kind == .series ? mapMovieGenreToTvGenre(genreId) : genreId
        }
        return output
    }

    private func parseSmartSearch(_ rawQuery: String) -> SmartSearchRequest? {
        let lowered = rawQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let similar = firstRegexCapture(pattern: #"(?:movies?|shows?|series|films?)\s+like\s+(.+)"#, in: lowered) {
            let scope: SmartSearchScope = lowered.contains("show") || lowered.contains("series") ? .shows : .movies
            let clean = similar.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return SmartSearchRequest(
                interpretation: "Similar to \"\(clean.capitalized)\"",
                scope: scope,
                genreId: nil,
                genreName: nil,
                sort: .popular,
                minVotes: nil,
                limit: nil,
                similarTo: clean
            )
        }

        let smartWords = ["top", "best", "popular", "trending", "new", "latest"]
        guard smartWords.contains(where: { lowered.contains($0) }) else { return nil }

        let genreMap = [
            "horror": ("27", "Horror"),
            "comedy": ("35", "Comedy"),
            "action": ("28", "Action"),
            "drama": ("18", "Drama"),
            "thriller": ("53", "Thriller"),
            "sci-fi": ("878", "Sci-Fi"),
            "science fiction": ("878", "Sci-Fi"),
            "romance": ("10749", "Romance"),
            "animation": ("16", "Animation"),
            "anime": ("16", "Anime"),
            "documentary": ("99", "Documentary"),
            "crime": ("80", "Crime"),
            "fantasy": ("14", "Fantasy"),
            "adventure": ("12", "Adventure"),
            "mystery": ("9648", "Mystery"),
            "war": ("10752", "War"),
            "western": ("37", "Western"),
            "family": ("10751", "Family"),
            "history": ("36", "History")
        ]
        let matchedGenre = genreMap.first { lowered.contains($0.key) }?.value
        let isAnime = lowered.contains("anime")
        let isShows = lowered.contains("show") || lowered.contains("series")
        let isMovies = lowered.contains("movie") || lowered.contains("film")
        let scope: SmartSearchScope = {
            if isAnime { return .anime }
            if isShows && !isMovies { return .shows }
            if isMovies && !isShows { return .movies }
            return .all
        }()
        let limit = firstRegexCapture(pattern: #"\btop\s+(\d+)\b"#, in: lowered).flatMap(Int.init)
        let sort: SmartSearchSort = {
            if lowered.contains("new") || lowered.contains("latest") { return .newest }
            if lowered.contains("best") || lowered.contains("top rated") || limit != nil { return .topRated }
            return .popular
        }()

        var parts: [String] = []
        if let limit { parts.append("Top \(limit)") }
        else {
            switch sort {
            case .topRated: parts.append("Best")
            case .newest: parts.append("Newest")
            case .popular: parts.append("Popular")
            }
        }
        if let genreName = matchedGenre?.1, !isAnime { parts.append(genreName) }
        parts.append(scopeLabel(scope))

        return SmartSearchRequest(
            interpretation: parts.joined(separator: " "),
            scope: scope,
            genreId: isAnime ? nil : matchedGenre?.0,
            genreName: matchedGenre?.1,
            sort: sort,
            minVotes: sort == .topRated ? "500" : nil,
            limit: limit,
            similarTo: nil
        )
    }

    private func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func scopeLabel(_ scope: SmartSearchScope) -> String {
        switch scope {
        case .all: return "Movies & Series"
        case .movies: return "Movies"
        case .shows: return "Series"
        case .anime: return "Anime"
        }
    }

    private func mapMovieGenreToTvGenre(_ genre: String) -> String {
        switch genre {
        case "28": return "10759"
        case "14", "878": return "10765"
        case "10752": return "10768"
        default: return genre
        }
    }

    private func interleaved(movies: [MediaItem], series: [MediaItem]) -> [MediaItem] {
        var output: [MediaItem] = []
        let maxCount = max(movies.count, series.count)
        for index in 0..<maxCount {
            if movies.indices.contains(index) { output.append(movies[index]) }
            if series.indices.contains(index) { output.append(series[index]) }
        }
        return uniqueItems(output)
    }

    private func uniqueItems<S: Sequence>(_ items: S) -> [MediaItem] where S.Element == MediaItem {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.kind.tmdbPath):\($0.tmdbId ?? 0):\($0.title)").inserted }
    }
}
