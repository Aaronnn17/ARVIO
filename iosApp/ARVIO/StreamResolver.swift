import Foundation

struct ResolvedStream: Identifiable, Hashable {
    let id = UUID()
    let addonName: String
    let sourceName: String
    let title: String
    let quality: String
    let size: String
    let url: URL?
    let isPlayable: Bool
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

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case url
        case externalUrl
        case infoHash
    }
}

@MainActor
final class StreamResolver: ObservableObject {
    @Published private(set) var streams: [ResolvedStream] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let tmdb: TmdbService
    private let addons: AddonService

    init(tmdb: TmdbService, addons: AddonService) {
        self.tmdb = tmdb
        self.addons = addons
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

            let resolved = await withTaskGroup(of: [ResolvedStream].self) { group in
                for addon in addons.addons {
                    group.addTask {
                        await Self.fetchStreams(addon: addon, type: type, contentId: contentId)
                    }
                }

                var all: [ResolvedStream] = []
                for await addonStreams in group {
                    all.append(contentsOf: addonStreams)
                }
                return all
            }
            streams = resolved.sorted { left, right in
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

    private static func fetchStreams(addon: InstalledAddon, type: String, contentId: String) async -> [ResolvedStream] {
        guard let url = streamURL(addon: addon, type: type, contentId: contentId) else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
            return decoded.streams?.map { stream in
                let rawURL = stream.url ?? stream.externalUrl
                let playableURL = rawURL.flatMap(URL.init(string:))
                let title = stream.title ?? stream.name ?? addon.name
                return ResolvedStream(
                    addonName: addon.name,
                    sourceName: stream.name ?? addon.name,
                    title: title,
                    quality: quality(from: [title, stream.description].compactMap { $0 }.joined(separator: " ")),
                    size: size(from: [title, stream.description].compactMap { $0 }.joined(separator: " ")),
                    url: playableURL,
                    isPlayable: playableURL.map(isDirectPlayable(url:)) ?? false
                )
            } ?? []
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
             value.contains("akamaized"))
    }
}
