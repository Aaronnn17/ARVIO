import Foundation

enum PluginRepositoryType: String, Codable, Hashable {
    case nuvioJS = "NUVIO_JS"
    case externalDEX = "EXTERNAL_DEX"

    var displayName: String {
        switch self {
        case .nuvioJS: return "Nuvio JS"
        case .externalDEX: return "Android DEX"
        }
    }

    var isExecutableOnIOS: Bool {
        switch self {
        case .nuvioJS: return true
        case .externalDEX: return false
        }
    }
}

struct PluginRepositoryRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var description: String?
    var enabled: Bool
    var lastUpdated: Int64
    var scraperCount: Int
    var type: PluginRepositoryType
}

struct PluginScraperRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var version: String
    var filename: String
    var supportedTypes: [String]
    var enabled: Bool
    var manifestEnabled: Bool
    var logo: String?
    var contentLanguage: [String]
    var repositoryId: String
    var formats: [String]?
    var type: PluginRepositoryType

    var supportsIOSExecution: Bool {
        type.isExecutableOnIOS
    }
}

private struct PluginManifestResponse: Decodable {
    let name: String
    let version: String?
    let description: String?
    let author: String?
    let scrapers: [PluginScraperManifest]?
    let providers: [PluginScraperManifest]?

    var activeScrapers: [PluginScraperManifest] {
        scrapers ?? providers ?? []
    }
}

private struct PluginScraperManifest: Decodable {
    let id: String
    let name: String
    let description: String?
    let version: String?
    let filename: String
    let supportedTypes: [String]?
    let enabled: Bool?
    let logo: String?
    let contentLanguage: [String]?
    let supportedPlatforms: [String]?
    let disabledPlatforms: [String]?
    let formats: [String]?
    let supportedFormats: [String]?
}

private struct ExternalRepoManifestResponse: Decodable {
    let name: String?
    let description: String?
    let manifestVersion: Int?
    let pluginLists: [String]
}

private struct ExternalPluginEntry: Decodable {
    let name: String
    let internalName: String
    let description: String?
    let version: Int?
    let apiVersion: Int?
    let status: Int?
    let authors: [String]?
    let tvTypes: [String]?
    let iconUrl: String?
    let url: String
    let fileSize: Int64?
    let repositoryUrl: String?
}

@MainActor
final class PluginService: ObservableObject {
    @Published private(set) var repositories: [PluginRepositoryRecord] = []
    @Published private(set) var scrapers: [PluginScraperRecord] = []
    @Published var pluginsEnabled = true
    @Published var groupStreamsByRepository = false
    @Published var repositoryInput = ""
    @Published var isLoading = false
    @Published var isTesting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var testResults: [String] = []

    private let repositoriesKey = "arvio_ios_plugin_repositories"
    private let scrapersKey = "arvio_ios_plugin_scrapers"
    private let enabledKey = "arvio_ios_plugins_enabled"
    private let groupingKey = "arvio_ios_plugin_group_streams_by_repository"
    private let maxScraperCodeBytes = 5 * 1024 * 1024
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        loadLocal()
    }

    var enabledScrapers: [PluginScraperRecord] {
        guard pluginsEnabled else { return [] }
        return scrapers.filter { $0.enabled && $0.manifestEnabled }
    }

    func addRepository() async {
        let input = repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = "Enter a repository URL or short code."
            return
        }
        await installRepository(input)
    }

    func installRepository(_ rawInput: String) async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }

        do {
            let resolved = try await resolveInput(rawInput)
            if let nuvio = try? await fetchNuvioRepository(resolved) {
                upsert(repository: nuvio.repository, scrapers: nuvio.scrapers)
                repositoryInput = ""
                successMessage = "Added \(nuvio.repository.name) with \(nuvio.scrapers.filter(\.supportsIOSExecution).count) iOS executable scraper(s)."
                return
            }
            let external = try await fetchExternalRepository(resolved)
            upsert(repository: external.repository, scrapers: external.scrapers)
            repositoryInput = ""
            successMessage = "Added \(external.repository.name). Android DEX plugins are visible on iOS but cannot execute natively."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeRepository(_ repository: PluginRepositoryRecord) {
        repositories.removeAll { $0.id == repository.id }
        scrapers.removeAll { $0.repositoryId == repository.id }
        saveLocal()
        successMessage = "Removed \(repository.name)."
    }

    func refreshRepository(_ repository: PluginRepositoryRecord) async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }

        do {
            switch repository.type {
            case .nuvioJS:
                let fetched = try await fetchNuvioRepository(repository.url)
                upsert(repository: fetched.repository, scrapers: fetched.scrapers)
                successMessage = "Refreshed \(fetched.repository.name)."
            case .externalDEX:
                let fetched = try await fetchExternalRepository(repository.url)
                upsert(repository: fetched.repository, scrapers: fetched.scrapers)
                successMessage = "Refreshed \(fetched.repository.name). Android DEX execution remains Android-only."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleScraper(_ scraper: PluginScraperRecord) {
        guard let index = scrapers.firstIndex(where: { $0.id == scraper.id }) else { return }
        if !scrapers[index].enabled && !scrapers[index].supportsIOSExecution {
            errorMessage = "\(scrapers[index].name) is an Android-only scraper runtime on iOS."
            return
        }
        scrapers[index].enabled.toggle()
        saveLocal()
    }

    func toggleAllScrapers(in repository: PluginRepositoryRecord, enabled: Bool) {
        for index in scrapers.indices where scrapers[index].repositoryId == repository.id {
            scrapers[index].enabled = enabled && scrapers[index].supportsIOSExecution && scrapers[index].manifestEnabled
        }
        if enabled && repository.type == .externalDEX {
            errorMessage = "Android DEX scrapers cannot execute on iOS."
        }
        saveLocal()
    }

    func resolveStreams(
        tmdbId: String,
        mediaType: String,
        season: Int?,
        episode: Int?,
        customUserAgent: String
    ) async -> [ResolvedStream] {
        let runnableScrapers = enabledScrapers
            .filter { $0.supportsIOSExecution && $0.supportsType(mediaType) }
            .compactMap { scraper -> (PluginScraperRecord, String)? in
                guard let code = scraperCode(scraper), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return (scraper, code)
            }

        guard !runnableScrapers.isEmpty else { return [] }

        return await withTaskGroup(of: [ResolvedStream].self) { group in
            for (scraper, code) in runnableScrapers {
                group.addTask {
                    await NuvioJSRuntime.execute(
                        scraper: scraper,
                        code: code,
                        tmdbId: tmdbId,
                        mediaType: mediaType,
                        season: season,
                        episode: episode,
                        customUserAgent: customUserAgent
                    )
                }
            }

            var streams: [ResolvedStream] = []
            for await scraperStreams in group {
                streams.append(contentsOf: scraperStreams)
            }
            return Array(streams.uniquedByPlaybackURL().prefix(150))
        }
    }

    func setPluginsEnabled(_ enabled: Bool) {
        pluginsEnabled = enabled
        saveLocal()
    }

    func setGroupStreamsByRepository(_ enabled: Bool) {
        groupStreamsByRepository = enabled
        saveLocal()
    }

    func testScraper(_ scraper: PluginScraperRecord) async {
        isTesting = true
        errorMessage = nil
        successMessage = nil
        testResults = []
        defer { isTesting = false }

        if scraper.supportsIOSExecution {
            successMessage = "Scraper test queued."
        } else {
            errorMessage = "\(scraper.name) uses an Android runtime. iOS can manage it, but cannot execute it yet."
        }
    }

    private func upsert(repository: PluginRepositoryRecord, scrapers incomingScrapers: [PluginScraperRecord]) {
        repositories.removeAll { normalizedURL($0.url) == normalizedURL(repository.url) || $0.id == repository.id }
        repositories.append(repository)
        repositories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        scrapers.removeAll { $0.repositoryId == repository.id }
        scrapers.append(contentsOf: incomingScrapers)
        scrapers.sort {
            if $0.repositoryId == $1.repositoryId {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.repositoryId < $1.repositoryId
        }
        saveLocal()
    }

    private func fetchNuvioRepository(_ rawURL: String) async throws -> (repository: PluginRepositoryRecord, scrapers: [PluginScraperRecord]) {
        let manifestURL = canonicalNuvioManifestURL(rawURL)
        guard let url = URL(string: manifestURL) else { throw ArvioError.invalidURL(manifestURL) }
        let manifest: PluginManifestResponse = try await JSONClient().request(url, headers: ["User-Agent": "ARVIO-iOS/1.0"])
        let repositoryId = stableId(manifestURL)
        let repository = PluginRepositoryRecord(
            id: repositoryId,
            name: manifest.name,
            url: manifestURL,
            description: manifest.description ?? manifest.author,
            enabled: true,
            lastUpdated: nowMillis(),
            scraperCount: manifest.activeScrapers.count,
            type: .nuvioJS
        )
        var records: [PluginScraperRecord] = []
        for entry in manifest.activeScrapers {
            let scraperId = "\(repositoryId)-\(entry.id)"
            let supportsIOS = Self.isSupportedOnIOS(entry)
            if supportsIOS, let code = try? await fetchNuvioScraperCode(entry: entry, manifestURL: manifestURL) {
                saveScraperCode(code, scraperId: scraperId)
            }
            records.append(PluginScraperRecord(
                id: scraperId,
                name: entry.name,
                description: entry.description ?? "",
                version: entry.version ?? manifest.version ?? "1",
                filename: entry.filename,
                supportedTypes: entry.supportedTypes ?? ["movie", "tv"],
                enabled: supportsIOS && (entry.enabled ?? true),
                manifestEnabled: supportsIOS && (entry.enabled ?? true),
                logo: entry.logo,
                contentLanguage: entry.contentLanguage ?? [],
                repositoryId: repositoryId,
                formats: entry.formats ?? entry.supportedFormats,
                type: .nuvioJS
            ))
        }
        return (repository, records)
    }

    private static func isSupportedOnIOS(_ entry: PluginScraperManifest) -> Bool {
        let platforms = (entry.supportedPlatforms ?? []).map { $0.lowercased() }
        let disabled = (entry.disabledPlatforms ?? []).map { $0.lowercased() }
        if disabled.contains("ios") || disabled.contains("apple") {
            return false
        }
        if platforms.isEmpty {
            return true
        }
        return platforms.contains("ios") ||
            platforms.contains("apple") ||
            platforms.contains("mobile") ||
            platforms.contains("all") ||
            platforms.contains("web")
    }

    private func fetchNuvioScraperCode(entry: PluginScraperManifest, manifestURL: String) async throws -> String {
        let codeURL = absoluteURL(entry.filename, relativeTo: URL(string: manifestURL)!)
        guard let url = URL(string: codeURL) else { throw ArvioError.invalidURL(codeURL) }

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.setValue("ARVIO-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let (_, response) = try? await URLSession.shared.data(for: headRequest),
           let http = response as? HTTPURLResponse,
           let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
           length > maxScraperCodeBytes {
            throw ArvioError.requestFailed("Scraper \(entry.name) is too large")
        }

        let data = try await fetchData(url)
        guard data.count <= maxScraperCodeBytes else {
            throw ArvioError.requestFailed("Scraper \(entry.name) is too large")
        }
        guard let code = String(data: data, encoding: .utf8) else {
            throw ArvioError.decodingFailed
        }
        return code
    }

    private func fetchExternalRepository(_ rawURL: String) async throws -> (repository: PluginRepositoryRecord, scrapers: [PluginScraperRecord]) {
        guard let url = URL(string: sanitizeScheme(rawURL)) else { throw ArvioError.invalidURL(rawURL) }
        let data = try await fetchData(url)
        let plugins: [ExternalPluginEntry]
        let name: String
        let description: String?

        if let manifest = try? decoder.decode(ExternalRepoManifestResponse.self, from: data) {
            name = manifest.name ?? url.host ?? "External Repository"
            description = manifest.description
            var combined: [ExternalPluginEntry] = []
            for listURL in manifest.pluginLists {
                guard let resolved = URL(string: absoluteURL(listURL, relativeTo: url)) else { continue }
                if let entries = try? await fetchExternalPluginList(resolved) {
                    combined.append(contentsOf: entries)
                }
            }
            plugins = combined
        } else if let direct = try? decoder.decode([ExternalPluginEntry].self, from: data) {
            name = url.host ?? "External Repository"
            description = "External Android extension list"
            plugins = direct
        } else {
            throw ArvioError.decodingFailed
        }

        let repositoryId = stableId(url.absoluteString)
        let repository = PluginRepositoryRecord(
            id: repositoryId,
            name: name,
            url: url.absoluteString,
            description: description,
            enabled: true,
            lastUpdated: nowMillis(),
            scraperCount: plugins.count,
            type: .externalDEX
        )
        let records = plugins.map { plugin in
            PluginScraperRecord(
                id: "\(repositoryId)-\(plugin.internalName)",
                name: plugin.name,
                description: plugin.description ?? "",
                version: String(plugin.version ?? plugin.apiVersion ?? 1),
                filename: plugin.url,
                supportedTypes: plugin.tvTypes ?? ["movie", "tv"],
                enabled: false,
                manifestEnabled: (plugin.status ?? 1) == 1,
                logo: plugin.iconUrl,
                contentLanguage: [],
                repositoryId: repositoryId,
                formats: nil,
                type: .externalDEX
            )
        }
        return (repository, records)
    }

    private func fetchExternalPluginList(_ url: URL) async throws -> [ExternalPluginEntry] {
        let data = try await fetchData(url)
        return (try? decoder.decode([ExternalPluginEntry].self, from: data)) ?? []
    }

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ARVIO-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Request failed for \(url.absoluteString)")
        }
        return data
    }

    private func resolveInput(_ input: String) async throws -> String {
        let trimmed = sanitizeScheme(input.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { throw ArvioError.invalidURL(input) }
        guard isShortCode(trimmed) else { return trimmed }

        guard let shortURL = URL(string: "https://cutt.ly/\(trimmed)") else { return trimmed }
        var request = URLRequest(url: shortURL)
        request.httpMethod = "HEAD"
        request.setValue("ARVIO-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let final = response.url?.absoluteString, final != shortURL.absoluteString {
            return sanitizeScheme(final)
        }
        return trimmed
    }

    private func canonicalNuvioManifestURL(_ rawURL: String) -> String {
        let value = sanitizeScheme(rawURL).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.lowercased().hasSuffix("/manifest.json") || value.lowercased().hasSuffix(".json") {
            return value
        }
        return "\(value)/manifest.json"
    }

    private func sanitizeScheme(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeRange = trimmed.range(of: "://") else { return trimmed }
        let scheme = trimmed[..<schemeRange.lowerBound].lowercased()
        guard scheme != "http" && scheme != "https" else { return trimmed }
        return "https://\(trimmed[schemeRange.upperBound...])"
    }

    private func isShortCode(_ value: String) -> Bool {
        guard !value.contains("://"),
              !value.contains("/"),
              !value.contains("."),
              !value.isEmpty else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func absoluteURL(_ value: String, relativeTo base: URL) -> String {
        if let absolute = URL(string: value), absolute.scheme != nil {
            return sanitizeScheme(absolute.absoluteString)
        }
        return URL(string: value, relativeTo: base)?.absoluteURL.absoluteString ?? value
    }

    private func normalizedURL(_ value: String) -> String {
        sanitizeScheme(value).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private func stableId(_ value: String) -> String {
        let normalized = normalizedURL(value)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "plugin_repo_\(String(hash, radix: 16))"
    }

    private func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func loadLocal() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) != nil {
            pluginsEnabled = defaults.bool(forKey: enabledKey)
        }
        groupStreamsByRepository = defaults.bool(forKey: groupingKey)
        if let data = defaults.data(forKey: repositoriesKey),
           let decoded = try? decoder.decode([PluginRepositoryRecord].self, from: data) {
            repositories = decoded
        }
        if let data = defaults.data(forKey: scrapersKey),
           let decoded = try? decoder.decode([PluginScraperRecord].self, from: data) {
            scrapers = decoded
        }
    }

    private func saveLocal() {
        let defaults = UserDefaults.standard
        defaults.set(pluginsEnabled, forKey: enabledKey)
        defaults.set(groupStreamsByRepository, forKey: groupingKey)
        if let data = try? encoder.encode(repositories) {
            defaults.set(data, forKey: repositoriesKey)
        }
        if let data = try? encoder.encode(scrapers) {
            defaults.set(data, forKey: scrapersKey)
        }
    }

    private func scraperCode(_ scraper: PluginScraperRecord) -> String? {
        guard let data = try? Data(contentsOf: scraperCodeURL(scraperId: scraper.id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveScraperCode(_ code: String, scraperId: String) {
        let url = scraperCodeURL(scraperId: scraperId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = code.data(using: .utf8) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func scraperCodeURL(scraperId: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        let safeId = scraperId.map { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "_"
        }
        return base
            .appendingPathComponent("ARVIO", isDirectory: true)
            .appendingPathComponent("Scrapers", isDirectory: true)
            .appendingPathComponent(String(safeId) + ".js")
    }
}

private extension PluginScraperRecord {
    func supportsType(_ type: String) -> Bool {
        let normalized = type.lowercased() == "series" ? "tv" : type.lowercased()
        return supportedTypes.map { $0.lowercased() }.contains(normalized)
    }
}

private extension Array where Element == ResolvedStream {
    func uniquedByPlaybackURL() -> [ResolvedStream] {
        var seen = Set<String>()
        return filter { stream in
            let key = stream.url?.absoluteString ?? "\(stream.addonName)|\(stream.title)"
            return seen.insert(key).inserted
        }
    }
}
