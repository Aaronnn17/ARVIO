import Foundation

struct ResolvedStream: Identifiable, Hashable {
    let id = UUID()
    let addonId: String?
    let addonName: String
    let sourceName: String
    let title: String
    let quality: String
    let size: String
    let url: URL?
    let requestHeaders: [String: String]
    let subtitles: [ResolvedSubtitle]
    let isPlayable: Bool
    let resumePositionSeconds: Int?
}

struct ResolvedSubtitle: Identifiable, Hashable {
    let id: String
    let label: String
    let language: String
    let url: URL
}

private struct StremioStreamResponse: Decodable {
    let streams: [StremioStream]?
}

private struct StremioStream: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let externalUrl: String?
    let infoHash: String?
    let fileIdx: Int?
    let sources: [String]?
    let subtitles: [StremioSubtitle]?
    let behaviorHints: StremioBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case url
        case externalUrl
        case infoHash
        case fileIdx
        case sources
        case subtitles
        case behaviorHints
    }
}

private struct StremioSubtitle: Decodable {
    let id: String?
    let lang: String?
    let url: String?
}

private struct StremioBehaviorHints: Decodable {
    let filename: String?
    let notWebReady: Bool?
    let proxyHeaders: StremioProxyHeaders?
}

private struct StremioProxyHeaders: Decodable {
    let request: [String: String]?
    let response: [String: String]?
}

@MainActor
final class StreamResolver: ObservableObject {
    @Published private(set) var streams: [ResolvedStream] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let tmdb: TmdbService
    private let addons: AddonService
    private let settings: SettingsService
    private let iptv: IptvService
    private let plugins: PluginService

    init(tmdb: TmdbService, addons: AddonService, settings: SettingsService, iptv: IptvService, plugins: PluginService) {
        self.tmdb = tmdb
        self.addons = addons
        self.settings = settings
        self.iptv = iptv
        self.plugins = plugins
    }

    func resolve(item: MediaItem, season: Int = 1, episode: Int = 1) async {
        isLoading = true
        streams = []
        defer { isLoading = false }
        do {
            let externalIds = try await tmdb.externalIds(for: item)
            guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
                throw ArvioError.requestFailed("No IMDB id available for source lookup")
            }
            let contentId = item.kind == .movie ? imdbId : "\(imdbId):\(season):\(episode)"
            let type = item.kind.stremioType
            let profileSettings = settings.profileSettings
            let torrServerBaseUrl = profileSettings.torrServerBaseUrl
            let qualityRegexes = Self.qualityRegexes(from: profileSettings.qualityFiltersJson)

            let resolved = await withTaskGroup(of: [ResolvedStream].self) { group in
                for addon in addons.addons {
                    guard addon.isEnabled else { continue }
                    group.addTask {
                        await Self.fetchStreams(
                            addon: addon,
                            type: type,
                            contentId: contentId,
                            torrServerBaseUrl: torrServerBaseUrl,
                            customUserAgent: profileSettings.customUserAgent
                        )
                    }
                }

                var all: [ResolvedStream] = []
                for await addonStreams in group {
                    all.append(contentsOf: addonStreams)
                }
                return all
            }
            let homeServerStreams = await HomeServerService.resolveSources(
                item: item,
                externalIds: externalIds,
                season: season,
                episode: episode,
                settings: profileSettings
            )
            let iptvStreams = await iptv.resolveVodSources(
                item: item,
                externalIds: externalIds,
                season: season,
                episode: episode
            )
            let pluginStreams = await plugins.resolveStreams(
                tmdbId: item.tmdbId.map(String.init) ?? item.id,
                mediaType: item.kind == .movie ? "movie" : "tv",
                season: item.kind == .series ? season : nil,
                episode: item.kind == .series ? episode : nil,
                customUserAgent: profileSettings.customUserAgent
            )
            streams = Self.applyQualityFilters(to: resolved + pluginStreams + homeServerStreams + iptvStreams, regexes: qualityRegexes).map { stream in
                ResolvedStream(
                    addonId: stream.addonId,
                    addonName: stream.addonName,
                    sourceName: stream.sourceName,
                    title: stream.title,
                    quality: stream.quality,
                    size: stream.size,
                    url: stream.url,
                    requestHeaders: stream.requestHeaders,
                    subtitles: stream.subtitles,
                    isPlayable: stream.isPlayable,
                    resumePositionSeconds: item.positionSeconds
                )
            }
            .sorted { left, right in
                score(left, preferredLanguage: profileSettings.defaultAudioLanguage) >
                    score(right, preferredLanguage: profileSettings.defaultAudioLanguage)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func score(_ stream: ResolvedStream, preferredLanguage: String) -> Int {
        SharedCoreBridge.streamScore(
            quality: stream.quality,
            size: stream.size,
            addonName: stream.addonName,
            sourceName: stream.sourceName,
            title: stream.title,
            isPlayable: stream.isPlayable,
            preferredLanguage: preferredLanguage,
            cached: false
        )
    }

    private static func fetchStreams(
        addon: InstalledAddon,
        type: String,
        contentId: String,
        torrServerBaseUrl: String,
        customUserAgent: String
    ) async -> [ResolvedStream] {
        guard let url = streamURL(addon: addon, type: type, contentId: contentId) else { return [] }
        do {
            var request = URLRequest(url: url)
            let trimmedUserAgent = customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUserAgent.isEmpty {
                request.setValue(trimmedUserAgent, forHTTPHeaderField: "User-Agent")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
            var output: [ResolvedStream] = []
            for stream in decoded.streams ?? [] {
                let rawURL = stream.url ?? stream.externalUrl
                let split = rawURL.map(splitUrlAndHeaders) ?? (nil, [:])
                let hintHeaders = stream.behaviorHints?.proxyHeaders?.request ?? [:]
                let requestHeaders = playbackHeaders(extra: mergeRequestHeaders(base: hintHeaders, extra: split.1), customUserAgent: customUserAgent)
                let normalizedRawURL = split.0.flatMap(normalizePlaybackUrl)
                let resolvedRawURL = await resolveRedirectIfNeeded(rawUrl: normalizedRawURL, headers: requestHeaders)
                var playableURL = resolvedRawURL.flatMap(URL.init(string:))
                let title = stream.title ?? stream.name ?? addon.name
                let text = [title, stream.description].compactMap { $0 }.joined(separator: " ")
                if playableURL == nil,
                   let magnet = buildMagnet(for: stream, title: title),
                   let torrServerURL = await resolveTorrentViaTorrServer(
                    baseUrl: torrServerBaseUrl,
                    stream: stream,
                    magnet: magnet
                   ) {
                    playableURL = torrServerURL
                }
                let isPlayable = playableURL.map { url in
                    isDirectPlayable(url: url, behaviorHints: stream.behaviorHints)
                } ?? false
                let subtitles = (stream.subtitles ?? []).compactMap { subtitle -> ResolvedSubtitle? in
                    guard let rawUrl = subtitle.url,
                          let url = URL(string: rawUrl) else { return nil }
                    let language = subtitle.lang?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "sub"
                    return ResolvedSubtitle(
                        id: subtitle.id?.nilIfBlank ?? "\(language)-\(rawUrl)",
                        label: language.uppercased(),
                        language: language,
                        url: url
                    )
                }
                output.append(ResolvedStream(
                    addonId: addon.id,
                    addonName: addon.name,
                    sourceName: stream.name ?? addon.name,
                    title: title,
                    quality: quality(from: text),
                    size: size(from: text),
                    url: playableURL,
                    requestHeaders: requestHeaders,
                    subtitles: subtitles,
                    isPlayable: isPlayable,
                    resumePositionSeconds: nil
                ))
            }
            return output
        } catch {
            return []
        }
    }

    private static func streamURL(addon: InstalledAddon, type: String, contentId: String) -> URL? {
        guard var components = URLComponents(string: addon.manifestURL) else { return nil }
        let query = components.percentEncodedQuery
        var path = components.path
        if path.hasSuffix("/manifest.json") {
            path.removeLast("/manifest.json".count)
        }
        components.path = path + "/stream/\(type)/\(contentId).json"
        components.percentEncodedQuery = query
        return components.url
    }

    private static func quality(from text: String) -> String {
        let label = SharedCoreBridge.qualityLabel(from: text)
        return label == "Direct" ? "Unknown" : label
    }

    private static func size(from text: String) -> String {
        let pattern = #"(\d+\.?\d*)\s*(GB|MB|TB|KB)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return ""
        }
        return String(text[match])
    }

    private static func isDirectPlayable(url: URL, behaviorHints: StremioBehaviorHints?) -> Bool {
        if behaviorHints?.notWebReady == true { return false }
        let value = url.absoluteString.lowercased()
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return false }
        if value.contains("youtube.com/watch") || value.contains("youtu.be/") { return false }
        return true
    }

    private static func splitUrlAndHeaders(_ rawUrl: String) -> (String?, [String: String]) {
        guard let separator = rawUrl.firstIndex(of: "|") else {
            return (rawUrl.trimmingCharacters(in: .whitespacesAndNewlines), [:])
        }
        let baseUrl = String(rawUrl[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHeaders = String(rawUrl[rawUrl.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseUrl.isEmpty, !rawHeaders.isEmpty else {
            return (baseUrl.isEmpty ? rawUrl : baseUrl, [:])
        }

        var headers: [String: String] = [:]
        rawHeaders.split(separator: "&").forEach { entry in
            let entryString = String(entry)
            guard let equals = entryString.firstIndex(of: "=") else { return }
            let rawKey = String(entryString[..<equals])
            let rawValue = String(entryString[entryString.index(after: equals)...])
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            guard !key.isEmpty, !value.isEmpty, !key.contains("\n"), !key.contains("\r"), !value.contains("\n"), !value.contains("\r") else { return }
            headers[key] = value
        }
        return (baseUrl, headers)
    }

    private static func normalizePlaybackUrl(_ rawUrl: String) -> String? {
        let value = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("magnet:") { return nil }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return value
        }
        if value.hasPrefix("//") {
            return "https:\(value)"
        }
        if !value.contains("://"), value.contains(".") {
            return "https://\(value)"
        }
        return value
    }

    private static func playbackHeaders(extra: [String: String], customUserAgent: String) -> [String: String] {
        let userAgent = customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Accept": "*/*",
            "Accept-Encoding": "identity"
        ]
        for (key, value) in extra where isSafeHeader(key: key, value: value) {
            headers[key] = value
        }
        if headers.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }),
           !headers.keys.contains(where: { $0.caseInsensitiveCompare("Origin") == .orderedSame }),
           let referer = headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value,
           let origin = deriveOrigin(from: referer) {
            headers["Origin"] = origin
        }
        return headers
    }

    private static func mergeRequestHeaders(base: [String: String], extra: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in base where isSafeHeader(key: key, value: value) {
            output[key] = value
        }
        for (key, value) in extra where isSafeHeader(key: key, value: value) {
            output[key] = value
        }
        return output
    }

    private static func isSafeHeader(key: String, value: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty &&
            !value.isEmpty &&
            !key.contains("\n") &&
            !key.contains("\r") &&
            !value.contains("\n") &&
            !value.contains("\r")
    }

    private static func deriveOrigin(from referer: String) -> String? {
        guard let url = URL(string: referer),
              let scheme = url.scheme,
              let host = url.host else { return nil }
        if let port = url.port {
            let defaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            return defaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func shouldResolveRedirectBeforePlayback(_ rawUrl: String?) -> Bool {
        guard let rawUrl,
              let host = URL(string: rawUrl)?.host?.lowercased() else { return false }
        if rawUrl.localizedCaseInsensitiveContains(".m3u8") || rawUrl.localizedCaseInsensitiveContains(".mpd") {
            return false
        }
        return host.contains("torrentio") ||
            host.contains("strem") ||
            host.contains("comet") ||
            host.contains("mediafusion") ||
            host.contains("stremthru") ||
            host.contains("jackettio")
    }

    private static func resolveRedirectIfNeeded(rawUrl: String?, headers: [String: String]) async -> String? {
        guard let rawUrl, shouldResolveRedirectBeforePlayback(rawUrl) else { return rawUrl }
        guard let url = URL(string: rawUrl) else { return rawUrl }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.8
        config.timeoutIntervalForResource = 2.2
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        for (key, value) in headers where key.caseInsensitiveCompare("Range") != .orderedSame {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (_, response) = try await session.data(for: request)
            return response.url?.absoluteString.nilIfBlank ?? rawUrl
        } catch {
            return rawUrl
        }
    }

    private static func buildMagnet(for stream: StremioStream, title: String) -> String? {
        let hash = stream.infoHash?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "urn:btih:", with: "")
            .replacingOccurrences(of: "btih:", with: "") ?? ""
        guard !hash.isEmpty else { return nil }

        let displayName = stream.behaviorHints?.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? stream.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? title
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [
            URLQueryItem(name: "xt", value: "urn:btih:\(hash)"),
            URLQueryItem(name: "dn", value: displayName)
        ] + (stream.sources ?? [])
            .map { $0.replacingOccurrences(of: "tracker:", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") || $0.hasPrefix("udp://") }
            .map { URLQueryItem(name: "tr", value: $0) }
        return components.string
    }

    private static func normalizeTorrServerBaseUrl(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "http:\(trimmed)"
        }
        return "http://\(trimmed)"
    }

    private static func resolveTorrentViaTorrServer(baseUrl: String, stream: StremioStream, magnet: String) async -> URL? {
        let configured = normalizeTorrServerBaseUrl(baseUrl)
        let candidates = [configured, "http://127.0.0.1:8090", "http://localhost:8090"]
            .filter { !$0.isEmpty }
            .uniqued()
        let endpointTemplates = [
            "/stream?m3u&link=%@",
            "/torrent/play?m3u=true&link=%@"
        ]

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 1.5
        sessionConfig.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: sessionConfig)

        for base in candidates {
            for template in endpointTemplates {
                guard let encodedMagnet = magnet.addingPercentEncoding(withAllowedCharacters: .arvioQueryValueAllowed),
                      let endpoint = URL(string: base + String(format: template, encodedMagnet)) else { continue }
                var request = URLRequest(url: endpoint)
                request.httpMethod = "GET"
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                    let body = String(decoding: data, as: UTF8.self)
                    if let resolved = pickBestM3uUrl(base: base, m3u: body, fileIdx: stream.fileIdx) {
                        return URL(string: resolved)
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private static func pickBestM3uUrl(base: String, m3u: String, fileIdx: Int?) -> String? {
        let entries = m3u
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { line in
                if line.lowercased().hasPrefix("http://") || line.lowercased().hasPrefix("https://") {
                    return line
                }
                if line.hasPrefix("/") {
                    return base + line
                }
                return base + "/" + line
            }
        guard !entries.isEmpty else { return nil }
        if let fileIdx,
           let match = entries.first(where: { $0.contains("index=\(fileIdx)") || $0.contains("file=\(fileIdx)") }) {
            return match
        }
        return entries.first
    }

    private static func qualityRegexes(from json: String) -> [NSRegularExpression] {
        guard let data = json.data(using: .utf8),
              let filters = try? JSONDecoder().decode([QualityFilterConfig].self, from: data) else {
            return []
        }
        return filters
            .filter { $0.enabled && !$0.regexPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { try? NSRegularExpression(pattern: $0.regexPattern, options: [.caseInsensitive]) }
    }

    private static func applyQualityFilters(to streams: [ResolvedStream], regexes: [NSRegularExpression]) -> [ResolvedStream] {
        guard !regexes.isEmpty else { return streams }
        return streams.filter { stream in
            let text = [stream.quality, stream.sourceName, stream.title, stream.size].joined(separator: " ")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regexes.allSatisfy { regex in
                regex.firstMatch(in: text, range: range) == nil
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension CharacterSet {
    static let arvioQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }()
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
