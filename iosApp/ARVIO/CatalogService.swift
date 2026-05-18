import Foundation

enum CatalogSourceType: String, Codable, Hashable {
    case preinstalled = "PREINSTALLED"
    case trakt = "TRAKT"
    case mdblist = "MDBLIST"
    case addon = "ADDON"
    case homeServer = "HOME_SERVER"
}

enum CatalogKind: String, Codable, Hashable {
    case standard = "STANDARD"
    case collection = "COLLECTION"
    case collectionRail = "COLLECTION_RAIL"
}

enum CollectionTileShape: String, Codable, Hashable {
    case landscape = "LANDSCAPE"
    case poster = "POSTER"
}

struct CatalogConfig: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var sourceType: CatalogSourceType
    var sourceUrl: String?
    var sourceRef: String?
    var isPreinstalled: Bool
    var addonId: String?
    var addonCatalogType: String?
    var addonCatalogId: String?
    var addonName: String?
    var kind: CatalogKind
    var collectionDescription: String?
    var collectionCoverImageUrl: String?
    var collectionHeroImageUrl: String?
    var collectionClearLogoUrl: String?
    var collectionTileShape: CollectionTileShape
    var collectionHideTitle: Bool

    init(
        id: String,
        title: String,
        sourceType: CatalogSourceType = .preinstalled,
        sourceUrl: String? = nil,
        sourceRef: String? = nil,
        isPreinstalled: Bool = false,
        addonId: String? = nil,
        addonCatalogType: String? = nil,
        addonCatalogId: String? = nil,
        addonName: String? = nil,
        kind: CatalogKind = .standard,
        collectionDescription: String? = nil,
        collectionCoverImageUrl: String? = nil,
        collectionHeroImageUrl: String? = nil,
        collectionClearLogoUrl: String? = nil,
        collectionTileShape: CollectionTileShape = .landscape,
        collectionHideTitle: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.sourceUrl = sourceUrl
        self.sourceRef = sourceRef
        self.isPreinstalled = isPreinstalled
        self.addonId = addonId
        self.addonCatalogType = addonCatalogType
        self.addonCatalogId = addonCatalogId
        self.addonName = addonName
        self.kind = kind
        self.collectionDescription = collectionDescription
        self.collectionCoverImageUrl = collectionCoverImageUrl
        self.collectionHeroImageUrl = collectionHeroImageUrl
        self.collectionClearLogoUrl = collectionClearLogoUrl
        self.collectionTileShape = collectionTileShape
        self.collectionHideTitle = collectionHideTitle
    }
}

struct CatalogRow: Identifiable, Hashable {
    let config: CatalogConfig
    let items: [MediaItem]

    var id: String { config.id }
}

private struct AddonCatalogResponse: Decodable {
    let metas: [AddonMeta]?
}

private struct AddonMeta: Decodable {
    let id: String?
    let type: String?
    let name: String?
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?

    func asMediaItem(defaultKind: MediaKind) -> MediaItem? {
        let resolvedKind: MediaKind
        if type == "movie" {
            resolvedKind = .movie
        } else if type == "series" || type == "tv" {
            resolvedKind = .series
        } else {
            resolvedKind = defaultKind
        }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let tmdbId = id.flatMap { raw -> Int? in
            let digits = raw.replacingOccurrences(of: "tmdb:", with: "")
            return Int(digits)
        }
        return MediaItem(
            id: "\(resolvedKind.tmdbPath)-\(id ?? title)",
            tmdbId: tmdbId,
            title: title,
            subtitle: resolvedKind.rawValue,
            year: String((releaseInfo ?? "").prefix(4)),
            duration: "",
            rating: imdbRating ?? "",
            kind: resolvedKind,
            progress: 0,
            palette: ["#10202a", "#071017"],
            posterPath: poster,
            backdropPath: background,
            overview: description
        )
    }
}

@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var catalogs: [CatalogConfig] = []
    @Published private(set) var rows: [CatalogRow] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let tmdb: TmdbService
    private let addons: AddonService
    private var activeProfileId = "default"

    init(cloud: CloudSyncService, tmdb: TmdbService, addons: AddonService) {
        self.cloud = cloud
        self.tmdb = tmdb
        self.addons = addons
        catalogs = Self.defaultCatalogs
    }

    func setActiveProfileId(_ profileId: String?) {
        let trimmed = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = trimmed.isEmpty ? "default" : trimmed
        loadFromCloud()
    }

    func loadFromCloud() {
        let profileCatalogs = cloud.payload.catalogsByProfile?[activeProfileId]
        let fallbackProfileCatalogs = cloud.payload.catalogsByProfile?.values.first
        let cloudCatalogs = profileCatalogs ?? fallbackProfileCatalogs ?? cloud.payload.catalogs
        let visibleCatalogs = cloudCatalogs?.filter { !hiddenCatalogIds.contains($0.id) }
        catalogs = visibleCatalogs?.nilIfEmpty ?? Self.defaultCatalogs
    }

    func reloadRows() async {
        loadFromCloud()
        isLoading = true
        defer { isLoading = false }

        let configs = catalogs.isEmpty ? Self.defaultCatalogs : catalogs
        var loadedRows: [CatalogRow] = []
        for config in configs {
            if let items = await loadItems(for: config), !items.isEmpty {
                loadedRows.append(CatalogRow(config: config, items: items))
            }
        }
        rows = loadedRows
        errorMessage = nil
    }

    func items(for config: CatalogConfig) async -> [MediaItem] {
        await loadItems(for: config) ?? []
    }

    var hiddenCatalogIds: Set<String> {
        let hidden = cloud.payload.hiddenPreinstalledByProfile?[activeProfileId] ??
            cloud.payload.hiddenPreinstalledByProfile?.values.first ??
            cloud.payload.hiddenPreinstalledCatalogs ?? []
        return Set(hidden)
    }

    func moveCatalog(_ config: CatalogConfig, direction: Int) async {
        guard let index = catalogs.firstIndex(where: { $0.id == config.id }) else { return }
        let target = index + direction
        guard catalogs.indices.contains(target) else { return }
        catalogs.swapAt(index, target)
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
        await reloadRows()
    }

    func hideCatalog(_ config: CatalogConfig) async {
        var hidden = hiddenCatalogIds
        hidden.insert(config.id)
        catalogs.removeAll { $0.id == config.id }
        await saveCatalogState(hiddenIds: Array(hidden))
        await reloadRows()
    }

    func restoreDefaultCatalogs() async {
        catalogs = Self.defaultCatalogs
        await saveCatalogState(hiddenIds: [])
        await reloadRows()
    }

    func addCatalog(title: String, sourceType: CatalogSourceType, sourceUrl: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanUrl.isEmpty else { return }
        let config = CatalogConfig(
            id: "ios_custom_\(UUID().uuidString)",
            title: cleanTitle,
            sourceType: sourceType,
            sourceUrl: cleanUrl,
            sourceRef: cleanUrl,
            isPreinstalled: false
        )
        catalogs.append(config)
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
        await reloadRows()
    }

    func renameCatalog(_ config: CatalogConfig, title: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let index = catalogs.firstIndex(where: { $0.id == config.id }) else { return }
        catalogs[index].title = cleanTitle
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
        await reloadRows()
    }

    func deleteCatalog(_ config: CatalogConfig) async {
        if config.isPreinstalled {
            await hideCatalog(config)
            return
        }
        catalogs.removeAll { $0.id == config.id }
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
        await reloadRows()
    }

    private func saveCatalogState(hiddenIds: [String]) async {
        await cloud.save(catalogs: catalogs, hiddenPreinstalledCatalogIds: hiddenIds, profileId: activeProfileId)
    }

    private func loadItems(for config: CatalogConfig) async -> [MediaItem]? {
        do {
            switch config.sourceType {
            case .preinstalled:
                return try await tmdb.catalogItems(for: config)
            case .addon:
                return try await loadAddonCatalog(config)
            case .trakt, .mdblist:
                return try await tmdb.listItems(from: config.sourceUrl ?? config.sourceRef, fallbackKind: fallbackKind(for: config))
            case .homeServer:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func loadAddonCatalog(_ config: CatalogConfig) async throws -> [MediaItem] {
        guard let addon = addons.addons.first(where: { $0.isEnabled && ($0.id == config.addonId || $0.name == config.addonName) }),
              let type = config.addonCatalogType ?? config.sourceRef?.components(separatedBy: "/").first,
              let catalogId = config.addonCatalogId ?? config.sourceRef?.components(separatedBy: "/").last else {
            return []
        }
        guard var components = URLComponents(string: addon.manifestURL) else { return [] }
        let query = components.percentEncodedQuery
        var path = components.path
        if path.hasSuffix("/manifest.json") {
            path.removeLast("/manifest.json".count)
        }
        components.path = path + "/catalog/\(type)/\(catalogId).json"
        components.percentEncodedQuery = query
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let decoded = try JSONDecoder().decode(AddonCatalogResponse.self, from: data)
        return decoded.metas?.compactMap { $0.asMediaItem(defaultKind: type == "series" ? .series : .movie) } ?? []
    }

    private func fallbackKind(for config: CatalogConfig) -> MediaKind {
        let value = [config.sourceUrl, config.sourceRef, config.title].compactMap { $0 }.joined(separator: " ").lowercased()
        if value.contains("show") || value.contains("series") || value.contains("/tv") { return .series }
        return .movie
    }

    static let defaultCatalogs: [CatalogConfig] = [
        CatalogConfig(id: "trending_movies", title: "Trending Movies", isPreinstalled: true),
        CatalogConfig(id: "trending_series", title: "Trending Series", isPreinstalled: true),
        CatalogConfig(id: "popular_movies", title: "Popular Movies", isPreinstalled: true),
        CatalogConfig(id: "popular_series", title: "Popular Series", isPreinstalled: true),
        CatalogConfig(id: "top_rated_movies", title: "Top Rated Movies", isPreinstalled: true),
        CatalogConfig(id: "top_rated_series", title: "Top Rated Series", isPreinstalled: true),
        CatalogConfig(id: "now_playing_movies", title: "Now Playing", isPreinstalled: true),
        CatalogConfig(id: "airing_today_series", title: "Airing Today", isPreinstalled: true)
    ]
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
