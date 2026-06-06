import Foundation

struct LocalWatchlistItem: Codable, Identifiable, Hashable {
    var tmdbId: Int
    var mediaType: String
    var title: String
    var posterPath: String?
    var backdropPath: String?
    var addedAt: Int64
    var sourceOrder: Int

    var id: String {
        "\(mediaType):\(tmdbId)"
    }

    init(
        tmdbId: Int,
        mediaType: String,
        title: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        addedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        sourceOrder: Int = Int.max
    ) {
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.addedAt = addedAt
        self.sourceOrder = sourceOrder
    }

    func asMediaItem() -> MediaItem {
        let kind: MediaKind = mediaType == "movie" ? .movie : .series
        return MediaItem(
            id: "local-watchlist-\(mediaType)-\(tmdbId)",
            tmdbId: tmdbId,
            title: title.isEmpty ? "Saved Item" : title,
            subtitle: kind.rawValue,
            year: "",
            duration: "Watchlist",
            rating: "",
            kind: kind,
            progress: 0,
            palette: ["#10202a", "#071017"],
            posterPath: posterPath,
            backdropPath: backdropPath
        )
    }
}

@MainActor
final class LocalWatchlistService: ObservableObject {
    @Published private(set) var items: [LocalWatchlistItem] = []
    @Published private(set) var hydratedItems: [MediaItem] = []
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let tmdb: TmdbService
    private let storagePrefix = "arvio.ios.localWatchlist."
    private var activeProfileId = "default"

    init(cloud: CloudSyncService, tmdb: TmdbService) {
        self.cloud = cloud
        self.tmdb = tmdb
        loadLocal()
    }

    func setActiveProfileId(_ profileId: String?) {
        activeProfileId = profileId?.nilIfBlank ?? "default"
        loadFromCloud()
        Task { await hydrate() }
    }

    func loadFromCloud() {
        if let profileItems = cloud.payload.watchlistByProfile?[activeProfileId] {
            items = sort(profileItems)
            saveLocal()
        } else {
            loadLocal()
        }
    }

    func load() async {
        loadFromCloud()
        await hydrate()
    }

    func add(_ item: MediaItem) async {
        guard let tmdbId = item.tmdbId else { return }
        let local = LocalWatchlistItem(
            tmdbId: tmdbId,
            mediaType: item.kind.tmdbPath,
            title: item.title,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            addedAt: Int64(Date().timeIntervalSince1970 * 1000),
            sourceOrder: 0
        )
        var next = items.filter { !($0.tmdbId == local.tmdbId && $0.mediaType == local.mediaType) }
        next.insert(local, at: 0)
        items = normalizeOrder(next)
        await persist()
        await hydrate()
    }

    func remove(_ item: MediaItem) async {
        guard let tmdbId = item.tmdbId else { return }
        items.removeAll { $0.tmdbId == tmdbId && $0.mediaType == item.kind.tmdbPath }
        await persist()
        await hydrate()
    }

    func remove(_ item: LocalWatchlistItem) async {
        items.removeAll { $0.id == item.id }
        await persist()
        await hydrate()
    }

    func contains(_ item: MediaItem) -> Bool {
        guard let tmdbId = item.tmdbId else { return false }
        return items.contains { $0.tmdbId == tmdbId && $0.mediaType == item.kind.tmdbPath }
    }

    func mergedWithTrakt(_ traktItems: [TraktWatchlistItem]) -> [MediaItem] {
        var seen = Set<String>()
        let traktMedia = traktItems.map { $0.asMediaItem() }
        let localMedia = hydratedItems.isEmpty ? items.map { $0.asMediaItem() } : hydratedItems
        return (localMedia + traktMedia).filter { item in
            let key = "\(item.kind.tmdbPath):\(item.tmdbId ?? 0)"
            return seen.insert(key).inserted
        }
    }

    private func persist() async {
        saveLocal()
        await cloud.save(watchlist: items, profileId: activeProfileId)
    }

    private func hydrate() async {
        var resolved: [MediaItem] = []
        for item in items.prefix(120) {
            let kind: MediaKind = item.mediaType == "movie" ? .movie : .series
            if let hydrated = try? await tmdb.itemDetails(tmdbId: item.tmdbId, kind: kind) {
                resolved.append(hydrated)
            } else {
                resolved.append(item.asMediaItem())
            }
        }
        hydratedItems = resolved
    }

    private func sort(_ values: [LocalWatchlistItem]) -> [LocalWatchlistItem] {
        values.sorted {
            if $0.sourceOrder != $1.sourceOrder {
                return $0.sourceOrder < $1.sourceOrder
            }
            return $0.addedAt > $1.addedAt
        }
    }

    private func normalizeOrder(_ values: [LocalWatchlistItem]) -> [LocalWatchlistItem] {
        sort(values).enumerated().map { index, value in
            var copy = value
            copy.sourceOrder = index
            return copy
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LocalWatchlistItem].self, from: data) else {
            items = []
            hydratedItems = []
            return
        }
        items = sort(decoded)
        hydratedItems = items.map { $0.asMediaItem() }
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private var storageKey: String {
        storagePrefix + activeProfileId
    }
}
