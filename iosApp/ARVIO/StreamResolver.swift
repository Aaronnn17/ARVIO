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
    let isPlayable: Bool
    let resumePositionSeconds: Int?
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
        case behaviorHints
    }
}

private struct StremioBehaviorHints: Decodable {
    let filename: String?
}

@MainActor
final class StreamResolver: ObservableObject {
    @Published private(set) var streams: [ResolvedStream] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let tmdb: TmdbService
    private let addons: AddonService
    private let settings: SettingsService

    init(tmdb: TmdbService, addons: AddonService, settings: SettingsService) {
        self.tmdb = tmdb
        self.addons = addons
        self.settings = settings
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
                    group.addTask {
                        await Self.fetchStreams(
                            addon: addon,
                            type: type,
                            contentId: contentId,
                            torrServerBaseUrl: torrServerBaseUrl
                        )
                    }
                }

                var all: [ResolvedStream] = []
                for await addonStreams in group {
                    all.append(contentsOf: addonStreams)
                }
                return all
            }
            streams = Self.applyQualityFilters(to: resolved, regexes: qualityRegexes).map { stream in
                ResolvedStream(
                    addonId: stream.addonId,
                    addonName: stream.addonName,
                    sourceName: stream.sourceName,
                    title: stream.title,
                    quality: stream.quality,
                    size: stream.size,
                    url: stream.url,
                    requestHeaders: stream.requestHeaders,
                    isPlayable: stream.isPlayable,
                    resumePositionSeconds: item.positionSeconds
                )
            }
            .sorted { left, right in
                score(left) > score(right)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func score(_ stream: ResolvedStream) -> Int {
        var value = stream.isPlayable ? 100 : 0
        if stream.quality.contains("4K") || stream.quality.contains("2160") { value += 40 }
        if stream.quality.contains("1080") { value += 25 }
        if stream.quality.contains("720") { value += 10 }
        return value
    }

    private static func fetchStreams(
        addon: InstalledAddon,
        type: String,
        contentId: String,
        torrServerBaseUrl: String
    ) async -> [ResolvedStream] {
        guard let url = streamURL(addon: addon, type: type, contentId: contentId) else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
            var output: [ResolvedStream] = []
            for stream in decoded.streams ?? [] {
                let rawURL = stream.url ?? stream.externalUrl
                let split = rawURL.map(splitUrlAndHeaders) ?? (nil, [:])
                var playableURL = split.0.flatMap(URL.init(string:))
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
                let isPlayable = playableURL.map(isDirectPlayable(url:)) ?? false
                output.append(ResolvedStream(
                    addonId: addon.id,
                    addonName: addon.name,
                    sourceName: stream.name ?? addon.name,
                    title: title,
                    quality: quality(from: text),
                    size: size(from: text),
                    url: playableURL,
                    requestHeaders: split.1,
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
        if text.range(of: "2160p|4K", options: [.regularExpression, .caseInsensitive]) != nil { return "4K" }
        if text.range(of: "1080p", options: [.regularExpression, .caseInsensitive]) != nil { return "1080p" }
        if text.range(of: "720p", options: [.regularExpression, .caseInsensitive]) != nil { return "720p" }
        if text.range(of: "480p", options: [.regularExpression, .caseInsensitive]) != nil { return "480p" }
        return "Unknown"
    }

    private static func size(from text: String) -> String {
        let pattern = #"(\d+\.?\d*)\s*(GB|MB|TB|KB)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return ""
        }
        return String(text[match])
    }

    private static func isDirectPlayable(url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return value.hasPrefix("http") &&
            (value.contains(".m3u8") ||
             value.contains(".mp4") ||
             value.contains(".mov") ||
             value.contains(".m4v") ||
             value.contains("googlevideo.com") ||
             value.contains("cloudflare") ||
             value.contains("akamaized") ||
             value.contains("/stream?") ||
             value.contains("/torrent/play?"))
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
            guard let equals = entry.firstIndex(of: "=") else { return }
            let rawKey = String(entry[..<equals])
            let valueStart = entry.index(equals, offsetBy: 1)
            let rawValue = String(entry[valueStart...])
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            guard !key.isEmpty, !value.isEmpty, !key.contains("\n"), !key.contains("\r"), !value.contains("\n"), !value.contains("\r") else { return }
            headers[key] = value
        }
        return (baseUrl, headers)
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
        guard !configured.isEmpty else { return nil }
        let candidates = [configured].uniqued()
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
