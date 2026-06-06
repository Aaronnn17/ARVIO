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

enum CollectionGroupKind: String, Codable, Hashable {
    case featured = "FEATURED"
    case service = "SERVICE"
    case genre = "GENRE"
    case decade = "DECADE"
    case franchise = "FRANCHISE"
    case network = "NETWORK"
}

enum CollectionSourceKind: String, Codable, Hashable {
    case addonCatalog = "ADDON_CATALOG"
    case tmdbGenre = "TMDB_GENRE"
    case tmdbPerson = "TMDB_PERSON"
    case tmdbCollection = "TMDB_COLLECTION"
    case tmdbKeyword = "TMDB_KEYWORD"
    case tmdbWatchProvider = "TMDB_WATCH_PROVIDER"
    case curatedIds = "CURATED_IDS"
    case mdblistPublic = "MDBLIST_PUBLIC"
}

struct CollectionSourceConfig: Codable, Hashable {
    var kind: CollectionSourceKind
    var mediaType: String?
    var addonId: String?
    var addonCatalogType: String?
    var addonCatalogId: String?
    var tmdbGenreId: Int?
    var tmdbPersonId: Int?
    var tmdbCollectionId: Int?
    var tmdbKeywordId: Int?
    var tmdbWatchProviderId: Int?
    var watchRegion: String?
    var sortBy: String?
    var curatedRefs: [String]?
    var mdblistSlug: String?

    init(
        kind: CollectionSourceKind,
        mediaType: String? = nil,
        addonId: String? = nil,
        addonCatalogType: String? = nil,
        addonCatalogId: String? = nil,
        tmdbGenreId: Int? = nil,
        tmdbPersonId: Int? = nil,
        tmdbCollectionId: Int? = nil,
        tmdbKeywordId: Int? = nil,
        tmdbWatchProviderId: Int? = nil,
        watchRegion: String? = nil,
        sortBy: String? = nil,
        curatedRefs: [String]? = nil,
        mdblistSlug: String? = nil
    ) {
        self.kind = kind
        self.mediaType = mediaType
        self.addonId = addonId
        self.addonCatalogType = addonCatalogType
        self.addonCatalogId = addonCatalogId
        self.tmdbGenreId = tmdbGenreId
        self.tmdbPersonId = tmdbPersonId
        self.tmdbCollectionId = tmdbCollectionId
        self.tmdbKeywordId = tmdbKeywordId
        self.tmdbWatchProviderId = tmdbWatchProviderId
        self.watchRegion = watchRegion
        self.sortBy = sortBy
        self.curatedRefs = curatedRefs
        self.mdblistSlug = mdblistSlug
    }
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
    var collectionGroup: CollectionGroupKind?
    var collectionDescription: String?
    var collectionCoverImageUrl: String?
    var collectionFocusGifUrl: String?
    var collectionHeroImageUrl: String?
    var collectionHeroGifUrl: String?
    var collectionHeroVideoUrl: String?
    var collectionClearLogoUrl: String?
    var collectionTileShape: CollectionTileShape
    var collectionHideTitle: Bool
    var collectionSources: [CollectionSourceConfig]
    var requiredAddonUrls: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType
        case sourceUrl
        case sourceRef
        case isPreinstalled
        case addonId
        case addonCatalogType
        case addonCatalogId
        case addonName
        case kind
        case collectionGroup
        case collectionDescription
        case collectionCoverImageUrl
        case collectionFocusGifUrl
        case collectionHeroImageUrl
        case collectionHeroGifUrl
        case collectionHeroVideoUrl
        case collectionClearLogoUrl
        case collectionTileShape
        case collectionHideTitle
        case collectionSources
        case requiredAddonUrls
    }

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
        collectionGroup: CollectionGroupKind? = nil,
        collectionDescription: String? = nil,
        collectionCoverImageUrl: String? = nil,
        collectionFocusGifUrl: String? = nil,
        collectionHeroImageUrl: String? = nil,
        collectionHeroGifUrl: String? = nil,
        collectionHeroVideoUrl: String? = nil,
        collectionClearLogoUrl: String? = nil,
        collectionTileShape: CollectionTileShape = .landscape,
        collectionHideTitle: Bool = false,
        collectionSources: [CollectionSourceConfig] = [],
        requiredAddonUrls: [String] = []
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
        self.collectionGroup = collectionGroup
        self.collectionDescription = collectionDescription
        self.collectionCoverImageUrl = collectionCoverImageUrl
        self.collectionFocusGifUrl = collectionFocusGifUrl
        self.collectionHeroImageUrl = collectionHeroImageUrl
        self.collectionHeroGifUrl = collectionHeroGifUrl
        self.collectionHeroVideoUrl = collectionHeroVideoUrl
        self.collectionClearLogoUrl = collectionClearLogoUrl
        self.collectionTileShape = collectionTileShape
        self.collectionHideTitle = collectionHideTitle
        self.collectionSources = collectionSources
        self.requiredAddonUrls = requiredAddonUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? container.decode(String.self, forKey: .title)) ?? "Catalog"
        sourceType = (try? container.decode(CatalogSourceType.self, forKey: .sourceType)) ?? .preinstalled
        sourceUrl = try? container.decode(String.self, forKey: .sourceUrl)
        sourceRef = try? container.decode(String.self, forKey: .sourceRef)
        isPreinstalled = (try? container.decode(Bool.self, forKey: .isPreinstalled)) ?? false
        addonId = try? container.decode(String.self, forKey: .addonId)
        addonCatalogType = try? container.decode(String.self, forKey: .addonCatalogType)
        addonCatalogId = try? container.decode(String.self, forKey: .addonCatalogId)
        addonName = try? container.decode(String.self, forKey: .addonName)
        kind = (try? container.decode(CatalogKind.self, forKey: .kind)) ?? .standard
        collectionGroup = try? container.decode(CollectionGroupKind.self, forKey: .collectionGroup)
        collectionDescription = try? container.decode(String.self, forKey: .collectionDescription)
        collectionCoverImageUrl = try? container.decode(String.self, forKey: .collectionCoverImageUrl)
        collectionFocusGifUrl = try? container.decode(String.self, forKey: .collectionFocusGifUrl)
        collectionHeroImageUrl = try? container.decode(String.self, forKey: .collectionHeroImageUrl)
        collectionHeroGifUrl = try? container.decode(String.self, forKey: .collectionHeroGifUrl)
        collectionHeroVideoUrl = try? container.decode(String.self, forKey: .collectionHeroVideoUrl)
        collectionClearLogoUrl = try? container.decode(String.self, forKey: .collectionClearLogoUrl)
        collectionTileShape = (try? container.decode(CollectionTileShape.self, forKey: .collectionTileShape)) ?? .landscape
        collectionHideTitle = (try? container.decode(Bool.self, forKey: .collectionHideTitle)) ?? false
        collectionSources = (try? container.decode([CollectionSourceConfig].self, forKey: .collectionSources)) ?? []
        requiredAddonUrls = (try? container.decode([String].self, forKey: .requiredAddonUrls)) ?? []
    }
}

struct CatalogRow: Identifiable, Hashable {
    let config: CatalogConfig
    let items: [MediaItem]

    var id: String { config.id }
}

struct CatalogDiscoveryResult: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let sourceType: CatalogSourceType
    let sourceUrl: String
    let creatorName: String?
    let itemCount: Int?
    let likes: Int?
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
    @Published private(set) var discoveryResults: [CatalogDiscoveryResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isDiscovering = false
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let tmdb: TmdbService
    private let addons: AddonService
    private let settings: SettingsService
    private var activeProfileId = "default"

    init(cloud: CloudSyncService, tmdb: TmdbService, addons: AddonService, settings: SettingsService) {
        self.cloud = cloud
        self.tmdb = tmdb
        self.addons = addons
        self.settings = settings
        catalogs = Self.defaultCatalogs
    }

    func setActiveProfileId(_ profileId: String?) {
        let trimmed = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = trimmed.isEmpty ? "default" : trimmed
        loadFromCloud()
    }

    func loadFromCloud() {
        let profileCatalogs = cloud.payload.catalogsByProfile?[activeProfileId]
        let cloudCatalogs = profileCatalogs ?? cloud.payload.catalogs
        let resolvedCatalogs = cloudCatalogs.map { mergeMissingPreinstalledDefaults(into: $0) }
        let visibleCatalogs = resolvedCatalogs?.filter { !hiddenCatalogIds.contains($0.id) }
        catalogs = visibleCatalogs?.nilIfEmpty ?? Self.defaultCatalogs
    }

    private func mergeMissingPreinstalledDefaults(into cloudCatalogs: [CatalogConfig]) -> [CatalogConfig] {
        var merged = cloudCatalogs
        let existingIds = Set(merged.map(\.id))
        for config in Self.defaultCatalogs where config.isPreinstalled && !existingIds.contains(config.id) {
            merged.append(config)
        }
        return merged
    }

    func reloadRows() async {
        loadFromCloud()
        isLoading = true
        defer { isLoading = false }

        let configs = catalogs.isEmpty ? Self.defaultCatalogs : catalogs
        var loadedRows: [CatalogRow] = []
        for config in configs where config.kind == .standard {
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

    func syncHomeServerCatalogs() async {
        let homeServerCatalogs = HomeServerService.catalogConfigs(
            from: HomeServerService.parseConnections(settings.profileSettings.homeServerConnectionJson)
        )
        let existingIds = Set(homeServerCatalogs.map(\.id))
        catalogs.removeAll { $0.sourceType == .homeServer && !existingIds.contains($0.id) }
        for config in homeServerCatalogs where !catalogs.contains(where: { $0.id == config.id }) {
            catalogs.append(config)
        }
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
        await reloadRows()
    }

    func syncAddonCatalogs() async {
        let addonIds = Set(addons.addons.map(\.id))
        catalogs.removeAll { config in
            config.sourceType == .addon &&
                config.id.hasPrefix("addon_") &&
                !(config.addonId.map { addonIds.contains($0) } ?? false)
        }

        for addon in addons.addons {
            for ref in addon.catalogRefs {
                let configId = addonCatalogConfigId(addon: addon, ref: ref)
                guard !catalogs.contains(where: { $0.id == configId }) else { continue }
                catalogs.append(CatalogConfig(
                    id: configId,
                    title: addonCatalogTitle(addon: addon, ref: ref),
                    sourceType: .addon,
                    sourceRef: "\(ref.type)/\(ref.id)",
                    isPreinstalled: false,
                    addonId: addon.id,
                    addonCatalogType: ref.type,
                    addonCatalogId: ref.id,
                    addonName: addon.name
                ))
            }
        }
        await saveCatalogState(hiddenIds: Array(hiddenCatalogIds))
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

    func addDiscoveredCatalog(_ result: CatalogDiscoveryResult) async {
        await addCatalog(title: result.title, sourceType: result.sourceType, sourceUrl: result.sourceUrl)
    }

    func searchCatalogLists(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            discoveryResults = []
            return
        }
        isDiscovering = true
        defer { isDiscovering = false }
        async let trakt = searchTraktCatalogLists(normalized)
        async let mdblist = searchMdblistCatalogLists(normalized)
        let traktResults = await trakt
        let mdblistResults = await mdblist
        let combined = traktResults + mdblistResults
        var seen = Set<String>()
        discoveryResults = combined
            .filter { seen.insert($0.sourceUrl.lowercased()).inserted }
            .sorted {
                let leftLikes = $0.likes ?? 0
                let rightLikes = $1.likes ?? 0
                if leftLikes != rightLikes { return leftLikes > rightLikes }
                return ($0.itemCount ?? 0) > ($1.itemCount ?? 0)
            }
            .prefix(24)
            .map { $0 }
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

    private func searchTraktCatalogLists(_ query: String) async -> [CatalogDiscoveryResult] {
        guard AppConfig.isCloudConfigured else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var components = URLComponents(string: AppConfig.traktProxyURL)
        components?.queryItems = [
            URLQueryItem(name: "path", value: "/search/list?query=\(encoded)&limit=40"),
            URLQueryItem(name: "method", value: "GET")
        ]
        guard let url = components?.url else { return [] }
        do {
            let data = try await catalogData(url: url, headers: proxyHeaders())
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let list = row["list"] as? [String: Any],
                      ((list["privacy"] as? String) ?? "public").caseInsensitiveCompare("public") == .orderedSame,
                      let ids = list["ids"] as? [String: Any],
                      let listSlug = (ids["slug"] as? String)?.nilIfBlank,
                      let title = (list["name"] as? String)?.nilIfBlank else { return nil }
                let user = list["user"] as? [String: Any]
                let userIds = user?["ids"] as? [String: Any]
                let userSlug = (userIds?["slug"] as? String)?.nilIfBlank ?? (user?["username"] as? String)?.nilIfBlank
                guard let userSlug else { return nil }
                return CatalogDiscoveryResult(
                    id: "trakt:\(userSlug):\(listSlug)",
                    title: title,
                    description: (list["description"] as? String)?.nilIfBlank,
                    sourceType: .trakt,
                    sourceUrl: "https://trakt.tv/users/\(userSlug)/lists/\(listSlug)",
                    creatorName: (user?["name"] as? String)?.nilIfBlank ?? userSlug,
                    itemCount: intValue(list["item_count"]),
                    likes: intValue(list["likes"])
                )
            }
        } catch {
            return []
        }
    }

    private func searchMdblistCatalogLists(_ query: String) async -> [CatalogDiscoveryResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://mdblist.com/toplists/?public_list_name=\(encoded)&preferences=bot_test_message") else {
            return []
        }
        do {
            let data = try await catalogData(url: url, headers: ["User-Agent": "ARVIO"])
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            return mdblistLinks(in: html)
        } catch {
            return []
        }
    }

    private func mdblistLinks(in html: String) -> [CatalogDiscoveryResult] {
        let pattern = #"<a[^>]+href=["']([^"']*/lists/[^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var results: [CatalogDiscoveryResult] = []
        for match in regex.matches(in: html, range: nsRange) {
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let rawHref = String(html[hrefRange])
            let title = stripHtml(String(html[titleRange])).nilIfBlank
            guard let title else { continue }
            let sourceUrl: String
            if rawHref.hasPrefix("http") {
                sourceUrl = rawHref
            } else if rawHref.hasPrefix("/") {
                sourceUrl = "https://mdblist.com\(rawHref)"
            } else {
                sourceUrl = "https://mdblist.com/\(rawHref)"
            }
            let path = sourceUrl.components(separatedBy: "mdblist.com/lists/").dropFirst().first ?? ""
            let parts = path
                .split(separator: "/")
                .map(String.init)
            guard parts.count >= 2 else { continue }
            results.append(CatalogDiscoveryResult(
                id: "mdblist:\(parts[0]):\(parts[1])",
                title: title,
                description: "Public MDBList catalog",
                sourceType: .mdblist,
                sourceUrl: sourceUrl,
                creatorName: parts.first,
                itemCount: nil,
                likes: nil
            ))
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.sourceUrl.lowercased()).inserted }
    }

    private func catalogData(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json,text/html,*/*", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Catalog discovery failed")
        }
        return data
    }

    private func proxyHeaders() -> [String: String] {
        [
            "apikey": AppConfig.supabaseAnonKey,
            "Authorization": "Bearer \(AppConfig.supabaseAnonKey)"
        ]
    }

    private func stripHtml(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func loadItems(for config: CatalogConfig) async -> [MediaItem]? {
        do {
            if config.kind == .collection {
                return try await loadCollectionCatalog(config)
            }
            switch config.sourceType {
            case .preinstalled:
                return try await tmdb.catalogItems(for: config)
            case .addon:
                return try await loadAddonCatalog(config)
            case .trakt, .mdblist:
                return try await tmdb.listItems(from: config.sourceUrl ?? config.sourceRef, fallbackKind: fallbackKind(for: config))
            case .homeServer:
                return await HomeServerService.loadCatalogItems(sourceRef: config.sourceRef, settings: settings.profileSettings)
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func loadCollectionCatalog(_ config: CatalogConfig) async throws -> [MediaItem] {
        var output: [MediaItem] = []
        for source in config.collectionSources {
            let remaining = max(8, 40 - output.count)
            let items = try await loadCollectionSource(source, limit: remaining)
            for item in items where !output.contains(where: { $0.kind == item.kind && $0.tmdbId == item.tmdbId && $0.title == item.title }) {
                output.append(item)
            }
            if output.count >= 40 { break }
        }
        return Array(output.prefix(40))
    }

    private func loadCollectionSource(_ source: CollectionSourceConfig, limit: Int) async throws -> [MediaItem] {
        switch source.kind {
        case .addonCatalog:
            let config = CatalogConfig(
                id: "collection_addon_\(source.addonCatalogType ?? "")_\(source.addonCatalogId ?? "")",
                title: "Collection",
                sourceType: .addon,
                isPreinstalled: true,
                addonId: source.addonId,
                addonCatalogType: source.addonCatalogType,
                addonCatalogId: source.addonCatalogId
            )
            return Array((try await loadAddonCatalog(config)).prefix(limit))
        case .tmdbGenre:
            guard let genreId = source.tmdbGenreId, let kind = mediaKind(from: source.mediaType) else { return [] }
            return try await tmdb.discoverItems(kind: kind, query: ["with_genres": "\(genreId)", "sort_by": source.sortBy ?? "popularity.desc"], limit: limit)
        case .tmdbPerson:
            guard let personId = source.tmdbPersonId, let kind = mediaKind(from: source.mediaType) else { return [] }
            let key = kind == .movie ? "with_crew" : "with_people"
            return try await tmdb.discoverItems(kind: kind, query: [key: "\(personId)", "sort_by": source.sortBy ?? "popularity.desc"], limit: limit)
        case .tmdbCollection:
            guard let collectionId = source.tmdbCollectionId else { return [] }
            return try await tmdb.collectionItems(collectionId: collectionId, limit: limit)
        case .tmdbKeyword:
            guard let keywordId = source.tmdbKeywordId else { return [] }
            if let kind = mediaKind(from: source.mediaType) {
                return try await tmdb.discoverItems(kind: kind, query: ["with_keywords": "\(keywordId)", "sort_by": source.sortBy ?? "popularity.desc"], limit: limit)
            }
            async let movies = tmdb.discoverItems(kind: .movie, query: ["with_keywords": "\(keywordId)", "sort_by": source.sortBy ?? "popularity.desc"], limit: limit / 2)
            async let shows = tmdb.discoverItems(kind: .series, query: ["with_keywords": "\(keywordId)", "sort_by": source.sortBy ?? "popularity.desc"], limit: limit / 2)
            let movieItems = try await movies
            let showItems = try await shows
            return movieItems + showItems
        case .tmdbWatchProvider:
            guard let providerId = source.tmdbWatchProviderId, let kind = mediaKind(from: source.mediaType) else { return [] }
            return try await tmdb.discoverItems(
                kind: kind,
                query: [
                    "with_watch_providers": "\(providerId)",
                    "watch_region": source.watchRegion?.nilIfBlank ?? "US",
                    "sort_by": source.sortBy ?? "popularity.desc"
                ],
                limit: limit
            )
        case .curatedIds:
            return try await tmdb.items(for: curatedRefs(source.curatedRefs), limit: limit)
        case .mdblistPublic:
            guard let slug = source.mdblistSlug?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                  !slug.isEmpty else { return [] }
            return try await tmdb.listItems(from: "https://mdblist.com/lists/\(slug)", fallbackKind: mediaKind(from: source.mediaType) ?? .movie)
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

    private func addonCatalogConfigId(addon: InstalledAddon, ref: AddonCatalogRef) -> String {
        "addon_\(stableId(addon.id))_\(stableId(ref.type))_\(stableId(ref.id))"
    }

    private func addonCatalogTitle(addon: InstalledAddon, ref: AddonCatalogRef) -> String {
        let name = ref.name?.nilIfBlank ?? ref.id
        if name.localizedCaseInsensitiveContains(addon.name) {
            return name
        }
        return "\(addon.name): \(name)"
    }

    private func stableId(_ raw: String) -> String {
        raw.lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .reduce(into: "") { $0.append($1) }
    }

    private func mediaKind(from raw: String?) -> MediaKind? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if value == "movie" || value == "movies" { return .movie }
        if value == "series" || value == "tv" || value == "show" || value == "shows" { return .series }
        return nil
    }

    private func curatedRefs(_ raw: [String]?) -> [(MediaKind, Int)] {
        (raw ?? []).compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = Int(parts[1]) else { return nil }
            let kind = mediaKind(from: parts[0])
            return kind.map { ($0, id) }
        }
    }

    static let defaultCatalogs: [CatalogConfig] = defaultTopLevelCatalogs + defaultCollectionRails + defaultCollectionCatalogs

    private static let defaultTopLevelCatalogs: [CatalogConfig] = [
        CatalogConfig(id: "trending_movies", title: "Trending in Movies", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/trending-movies", sourceRef: "mdblist:https://mdblist.com/lists/snoak/trending-movies", isPreinstalled: true),
        CatalogConfig(id: "trending_tv", title: "Trending in Shows", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/trakt-s-trending-shows", sourceRef: "mdblist:https://mdblist.com/lists/snoak/trakt-s-trending-shows", isPreinstalled: true),
        CatalogConfig(id: "trending_anime", title: "Trending in Anime", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/trending-anime-shows", sourceRef: "mdblist:https://mdblist.com/lists/snoak/trending-anime-shows", isPreinstalled: true),
        CatalogConfig(id: "top10_movies_today", title: "Top 10 Movies Today", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/top-10-movies-of-the-day", sourceRef: "mdblist:https://mdblist.com/lists/snoak/top-10-movies-of-the-day", isPreinstalled: true),
        CatalogConfig(id: "top10_shows_today", title: "Top 10 Shows Today", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/top-10-shows-of-the-day", sourceRef: "mdblist:https://mdblist.com/lists/snoak/top-10-shows-of-the-day", isPreinstalled: true),
        CatalogConfig(id: "just_added", title: "Just Added", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/latest-movies-digital-release", sourceRef: "mdblist:https://mdblist.com/lists/snoak/latest-movies-digital-release", isPreinstalled: true),
        CatalogConfig(id: "top_movies_week", title: "Top Movies This Week", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/linaspurinis/top-watched-movies-of-the-week", sourceRef: "mdblist:https://mdblist.com/lists/linaspurinis/top-watched-movies-of-the-week", isPreinstalled: true),
        CatalogConfig(id: "new_kdramas", title: "New in K-Dramas", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/latest-kdrama-shows", sourceRef: "mdblist:https://mdblist.com/lists/snoak/latest-kdrama-shows", isPreinstalled: true),
        CatalogConfig(id: "coming_soon", title: "Coming Soon", sourceType: .mdblist, sourceUrl: "https://mdblist.com/lists/snoak/upcoming-movies", sourceRef: "mdblist:https://mdblist.com/lists/snoak/upcoming-movies", isPreinstalled: true)
    ]

    private static let defaultCollectionRails: [CatalogConfig] = [
        CatalogConfig(id: "collection_rail_service", title: "Streaming Services", isPreinstalled: true, kind: .collectionRail, collectionGroup: .service),
        CatalogConfig(id: "collection_rail_genre", title: "Genres", isPreinstalled: true, kind: .collectionRail, collectionGroup: .genre),
        CatalogConfig(id: "collection_rail_franchise", title: "Franchises", isPreinstalled: true, kind: .collectionRail, collectionGroup: .franchise)
    ]

    private static let defaultCollectionCatalogs: [CatalogConfig] = [
        collection(
            id: "collection_service_netflix",
            title: "Netflix",
            group: .service,
            cover: "https://raw.githubusercontent.com/chrishudson918/images/46fd4f8c335a7c581a7dcdb7dfac268c68ef84fc/Landscape%20Streaming%20Services/netflix.jpegli.jpg",
            sources: [
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "movie", tmdbWatchProviderId: 8, watchRegion: "US", sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "series", tmdbWatchProviderId: 8, watchRegion: "US", sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_service_prime",
            title: "Prime Video",
            group: .service,
            cover: "https://raw.githubusercontent.com/mrtxiv/networks-video-collection/3486fc9a3d0efe59d1929e75f66021dc4e15bcb7/networks%20collection/amazonprime.png",
            sources: [
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "movie", tmdbWatchProviderId: 9, watchRegion: "US", sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "series", tmdbWatchProviderId: 9, watchRegion: "US", sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_service_disney",
            title: "Disney+",
            group: .service,
            cover: "https://raw.githubusercontent.com/chrishudson918/images/46fd4f8c335a7c581a7dcdb7dfac268c68ef84fc/Landscape%20Streaming%20Services/disney.jpegli.jpg",
            sources: [CollectionSourceConfig(kind: .mdblistPublic, mediaType: "all", mdblistSlug: "garycrawfordgc/disney-shows")]
        ),
        collection(
            id: "collection_service_hbo",
            title: "HBO Max",
            group: .service,
            cover: "https://raw.githubusercontent.com/mrtxiv/networks-video-collection/3486fc9a3d0efe59d1929e75f66021dc4e15bcb7/networks%20collection/hbomax.png",
            sources: [
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "movie", tmdbWatchProviderId: 1899, watchRegion: "US", sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbWatchProvider, mediaType: "series", tmdbWatchProviderId: 1899, watchRegion: "US", sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_genre_action",
            title: "Action",
            group: .genre,
            cover: "https://raw.githubusercontent.com/chrishudson918/images/main/Landscape%20Genres/action.jpegli.jpg",
            sources: [
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "movie", tmdbGenreId: 28, sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "series", tmdbGenreId: 10759, sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_genre_comedy",
            title: "Comedy",
            group: .genre,
            cover: "https://raw.githubusercontent.com/chrishudson918/images/main/Landscape%20Genres/comedy.jpegli.jpg",
            sources: [
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "movie", tmdbGenreId: 35, sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "series", tmdbGenreId: 35, sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_genre_horror",
            title: "Horror",
            group: .genre,
            cover: "https://raw.githubusercontent.com/chrishudson918/images/main/Landscape%20Genres/horror.jpegli.jpg",
            sources: [
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "movie", tmdbGenreId: 27, sortBy: "popularity.desc"),
                CollectionSourceConfig(kind: .tmdbGenre, mediaType: "series", tmdbGenreId: 9648, sortBy: "popularity.desc")
            ]
        ),
        collection(
            id: "collection_franchise_star_wars",
            title: "Star Wars",
            group: .franchise,
            cover: "https://raw.githubusercontent.com/elucidationvortex-source/nuviotemplate/refs/heads/main/images/Star-Wars.jpg",
            tileShape: .poster,
            sources: [CollectionSourceConfig(kind: .mdblistPublic, mediaType: "all", mdblistSlug: "jxduffy/star-wars-chronological-order")]
        ),
        collection(
            id: "collection_franchise_harry_potter",
            title: "Harry Potter",
            group: .franchise,
            cover: "https://raw.githubusercontent.com/elucidationvortex-source/nuviotemplate/refs/heads/main/images/Harry-Potter.jpg",
            tileShape: .poster,
            sources: [
                CollectionSourceConfig(kind: .tmdbCollection, tmdbCollectionId: 1241),
                CollectionSourceConfig(kind: .mdblistPublic, mediaType: "movie", mdblistSlug: "thebirdod/harry-potter-collection")
            ]
        ),
        collection(
            id: "collection_franchise_lotr",
            title: "Lord of the Rings",
            group: .franchise,
            cover: "https://raw.githubusercontent.com/elucidationvortex-source/nuviotemplate/refs/heads/main/images/Lord-of-the-Rings.jpg",
            tileShape: .poster,
            sources: [
                CollectionSourceConfig(kind: .tmdbCollection, tmdbCollectionId: 119),
                CollectionSourceConfig(kind: .mdblistPublic, mediaType: "movie", mdblistSlug: "spudhead15/lord-of-the-rings-and-hobbit-collection")
            ]
        )
    ]

    private static func collection(
        id: String,
        title: String,
        group: CollectionGroupKind,
        cover: String,
        tileShape: CollectionTileShape = .landscape,
        sources: [CollectionSourceConfig]
    ) -> CatalogConfig {
        CatalogConfig(
            id: id,
            title: title,
            sourceType: .preinstalled,
            isPreinstalled: true,
            kind: .collection,
            collectionGroup: group,
            collectionDescription: "\(title) collection",
            collectionCoverImageUrl: cover,
            collectionHeroImageUrl: cover,
            collectionTileShape: tileShape,
            collectionHideTitle: true,
            collectionSources: sources
        )
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
