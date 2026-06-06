import Foundation

struct SkipInterval: Identifiable, Hashable {
    let id: String
    let startSeconds: Double
    let endSeconds: Double
    let type: String
    let provider: String

    var label: String {
        switch type.lowercased() {
        case "op", "mixed-op", "intro":
            return "Skip Intro"
        case "recap":
            return "Skip Recap"
        case "ed", "mixed-ed", "outro":
            return "Skip Ending"
        default:
            return "Skip"
        }
    }
}

actor SkipIntroService {
    static let shared = SkipIntroService()

    private var intervalCache: [String: [SkipInterval]] = [:]
    private var malIdCache: [String: String?] = [:]

    func intervals(imdbId: String?, season: Int, episode: Int) async -> [SkipInterval] {
        guard let imdbId = imdbId?.trimmingCharacters(in: .whitespacesAndNewlines), !imdbId.isEmpty else {
            return []
        }
        let cacheKey = "\(imdbId):\(season):\(episode)"
        if let cached = intervalCache[cacheKey] {
            return cached
        }

        let introDb = await fetchIntroDb(imdbId: imdbId, season: season, episode: episode)
        if !introDb.isEmpty {
            intervalCache[cacheKey] = introDb
            return introDb
        }

        if let malId = await resolveMalId(imdbId: imdbId) {
            let aniSkip = await fetchAniSkip(malId: malId, episode: episode)
            intervalCache[cacheKey] = aniSkip
            return aniSkip
        }

        intervalCache[cacheKey] = []
        return []
    }

    private func fetchIntroDb(imdbId: String, season: Int, episode: Int) async -> [SkipInterval] {
        guard var components = URLComponents(string: "https://api.introdb.app/segments") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbId),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode))
        ]
        guard let url = components.url else { return [] }
        do {
            let response: IntroDbSegmentsResponse = try await getJson(url)
            var output: [SkipInterval] = []
            appendIntroDbSegment(response.recap, type: "recap", provider: "introdb", into: &output)
            appendIntroDbSegment(response.intro, type: "intro", provider: "introdb", into: &output)
            appendIntroDbSegment(response.outro, type: "outro", provider: "introdb", into: &output)
            return output.sorted { $0.startSeconds < $1.startSeconds }
        } catch {
            return []
        }
    }

    private func fetchAniSkip(malId: String, episode: Int) async -> [SkipInterval] {
        guard var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malId)/\(episode)") else {
            return []
        }
        components.queryItems = ["op", "ed", "recap", "mixed-op", "mixed-ed"].map {
            URLQueryItem(name: "types", value: $0)
        } + [URLQueryItem(name: "episodeLength", value: "0")]
        guard let url = components.url else { return [] }
        do {
            let response: AniSkipResponse = try await getJson(url)
            guard response.found else { return [] }
            return (response.results ?? []).compactMap { result in
                let start = result.interval.startTime
                let end = result.interval.endTime
                guard end > start, start >= 0 else { return nil }
                return SkipInterval(
                    id: "aniskip-\(result.skipType)-\(start)-\(end)",
                    startSeconds: start,
                    endSeconds: end,
                    type: result.skipType,
                    provider: "aniskip"
                )
            }
            .sorted { $0.startSeconds < $1.startSeconds }
        } catch {
            return []
        }
    }

    private func resolveMalId(imdbId: String) async -> String? {
        if let cached = malIdCache[imdbId] {
            return cached
        }
        guard var components = URLComponents(string: "https://arm.haglund.dev/api/v2/imdb") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "id", value: imdbId),
            URLQueryItem(name: "include", value: "myanimelist")
        ]
        guard let url = components.url else { return nil }
        do {
            let values: [ArmEntry] = try await getJson(url)
            let malId = values.first?.myanimelist.map(String.init)
            malIdCache[imdbId] = malId
            return malId
        } catch {
            malIdCache[imdbId] = nil
            return nil
        }
    }

    private func appendIntroDbSegment(_ segment: IntroDbSegment?, type: String, provider: String, into output: inout [SkipInterval]) {
        guard let segment else { return }
        let start = segment.startMs > 0 ? Double(segment.startMs) / 1000.0 : (segment.startSec ?? 0)
        let end = segment.endMs > 0 ? Double(segment.endMs) / 1000.0 : (segment.endSec ?? 0)
        guard end > start, start >= 0 else { return }
        output.append(SkipInterval(
            id: "\(provider)-\(type)-\(start)-\(end)",
            startSeconds: start,
            endSeconds: end,
            type: type,
            provider: provider
        ))
    }

    private func getJson<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Skip interval request failed")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct IntroDbSegmentsResponse: Decodable {
    let intro: IntroDbSegment?
    let recap: IntroDbSegment?
    let outro: IntroDbSegment?
}

private struct IntroDbSegment: Decodable {
    let startMs: Int64
    let endMs: Int64
    let startSec: Double?
    let endSec: Double?

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
        case startSec = "start_sec"
        case endSec = "end_sec"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startMs = (try? container.decode(Int64.self, forKey: .startMs)) ?? 0
        endMs = (try? container.decode(Int64.self, forKey: .endMs)) ?? 0
        startSec = try? container.decode(Double.self, forKey: .startSec)
        endSec = try? container.decode(Double.self, forKey: .endSec)
    }
}

private struct AniSkipResponse: Decodable {
    let found: Bool
    let results: [AniSkipResult]?
}

private struct AniSkipResult: Decodable {
    let interval: AniSkipInterval
    let skipType: String
}

private struct AniSkipInterval: Decodable {
    let startTime: Double
    let endTime: Double
}

private struct ArmEntry: Decodable {
    let myanimelist: Int?
}
