import Foundation

struct IptvPlaylistEntry: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var m3uUrl: String
    var epgUrl: String
    var enabled: Bool
}

struct IptvCloudProfileState: Codable, Equatable {
    var m3uUrl: String = ""
    var epgUrl: String = ""
    var favoriteGroups: [String] = []
    var favoriteChannels: [String] = []
    var hiddenGroups: [String] = []
    var groupOrder: [String] = []
    var playlists: [IptvPlaylistEntry] = []
    var tvSession: IptvTvSessionState = IptvTvSessionState()
}

struct IptvTvSessionState: Codable, Equatable {
    var lastChannelId: String = ""
    var lastGroupName: String = ""
    var lastFocusedZone: String = "GUIDE"
    var lastOpenedAt: Int64 = 0
}

struct IptvChannel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let streamUrl: String
    let group: String
    let logo: String?
    let epgId: String?
    let rawTitle: String
}

@MainActor
final class IptvService: ObservableObject {
    @Published private(set) var state = IptvCloudProfileState()
    @Published private(set) var channels: [IptvChannel] = []
    @Published private(set) var selectedGroup = "All"
    @Published private(set) var isLoading = false
    @Published private(set) var progressMessage = ""
    @Published var searchText = ""
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let storageKey = "arvio.ios.iptvState"
    private var activeProfileId = "default"

    init(cloud: CloudSyncService) {
        self.cloud = cloud
        loadLocal()
    }

    var groups: [String] {
        let rawGroups = channels.map { $0.group.isEmpty ? "Uncategorized" : $0.group }
        let unique = Array(Set(rawGroups)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return ["All", "Favorites"] + unique
    }

    var visibleChannels: [IptvChannel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return channels.filter { channel in
            let groupMatches = selectedGroup == "All" ||
                (selectedGroup == "Favorites" && state.favoriteChannels.contains(channel.id)) ||
                channel.group == selectedGroup
            let searchMatches = query.isEmpty || channel.name.localizedCaseInsensitiveContains(query)
            return groupMatches && searchMatches
        }
    }

    func loadFromCloud() {
        let payload = cloud.payload
        let cloudState = payload.iptvByProfile?[activeProfileId] ??
            payload.iptvByProfile?.values.first ??
            legacyState(from: payload)
        guard let cloudState else { return }
        state = cloudState
        selectedGroup = cloudState.tvSession.lastGroupName.isEmpty ? selectedGroup : cloudState.tvSession.lastGroupName
        saveLocal()
    }

    func setActiveProfileId(_ profileId: String?) {
        activeProfileId = profileId?.nilIfBlank ?? "default"
        loadFromCloud()
    }

    func setGroup(_ group: String) {
        selectedGroup = group
        state.tvSession.lastGroupName = group
        saveLocal()
    }

    func saveConfig(m3uUrl: String, epgUrl: String) async {
        let m3u = m3uUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let epg = epgUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        state.m3uUrl = m3u
        state.epgUrl = epg
        state.playlists = m3u.isEmpty ? [] : [
            IptvPlaylistEntry(id: "list_1", name: "List 1", m3uUrl: m3u, epgUrl: epg, enabled: true)
        ]
        saveLocal()
        await cloud.save(iptv: state, profileId: activeProfileId)
        await reload()
    }

    func reload() async {
        let playlists = activePlaylists()
        guard !playlists.isEmpty else {
            errorMessage = "Add an M3U playlist to load Live TV"
            return
        }
        isLoading = true
        progressMessage = "Loading channels..."
        defer {
            isLoading = false
            progressMessage = ""
        }
        do {
            var loaded: [IptvChannel] = []
            for playlist in playlists {
                loaded.append(contentsOf: try await fetchPlaylist(playlist))
            }
            channels = deduplicate(loaded)
            if !groups.contains(selectedGroup) {
                selectedGroup = "All"
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ channel: IptvChannel) async {
        if state.favoriteChannels.contains(channel.id) {
            state.favoriteChannels.removeAll { $0 == channel.id }
        } else {
            state.favoriteChannels.append(channel.id)
        }
        saveLocal()
        await cloud.save(iptv: state, profileId: activeProfileId)
    }

    func markOpened(_ channel: IptvChannel) {
        state.tvSession.lastChannelId = channel.id
        state.tvSession.lastGroupName = channel.group
        state.tvSession.lastFocusedZone = "PLAYER"
        state.tvSession.lastOpenedAt = Int64(Date().timeIntervalSince1970 * 1000)
        saveLocal()
    }

    private func activePlaylists() -> [IptvPlaylistEntry] {
        let configured = state.playlists.filter { $0.enabled && !$0.m3uUrl.isEmpty }
        if !configured.isEmpty { return configured }
        guard !state.m3uUrl.isEmpty else { return [] }
        return [IptvPlaylistEntry(id: "list_1", name: "List 1", m3uUrl: state.m3uUrl, epgUrl: state.epgUrl, enabled: true)]
    }

    private func fetchPlaylist(_ playlist: IptvPlaylistEntry) async throws -> [IptvChannel] {
        guard let url = URL(string: playlist.m3uUrl) else {
            throw ArvioError.invalidURL(playlist.m3uUrl)
        }
        progressMessage = "Downloading \(playlist.name)..."
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Playlist failed to load")
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ArvioError.decodingFailed
        }
        progressMessage = "Parsing channels..."
        return parseM3U(text)
    }

    private func parseM3U(_ text: String) -> [IptvChannel] {
        var result: [IptvChannel] = []
        var pending: (name: String, group: String, logo: String?, epgId: String?, raw: String)?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF") {
                let attributes = Self.attributes(from: line)
                let commaName = line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "Channel"
                let name = attributes["tvg-name"]?.nilIfBlank ?? commaName.nilIfBlank ?? "Channel"
                let group = attributes["group-title"]?.nilIfBlank ?? "Uncategorized"
                pending = (name, group, attributes["tvg-logo"]?.nilIfBlank, attributes["tvg-id"]?.nilIfBlank, line)
            } else if line.hasPrefix("http") {
                let meta = pending ?? ("Channel \(result.count + 1)", "Uncategorized", nil, nil, "")
                result.append(
                    IptvChannel(
                        id: stableChannelId(name: meta.name, epgId: meta.epgId, streamUrl: line, index: result.count),
                        name: meta.name,
                        streamUrl: line,
                        group: meta.group,
                        logo: meta.logo,
                        epgId: meta.epgId,
                        rawTitle: meta.raw
                    )
                )
                pending = nil
            }
        }
        return result
    }

    private func stableChannelId(name: String, epgId: String?, streamUrl: String, index: Int) -> String {
        let source = (epgId?.nilIfBlank ?? name + streamUrl).lowercased()
        let cleaned = source.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(cleaned).replacingOccurrences(of: "--", with: "-") + "-\(index)"
    }

    private func deduplicate(_ values: [IptvChannel]) -> [IptvChannel] {
        var seen = Set<String>()
        return values.filter { channel in
            let key = channel.name.lowercased() + "|" + channel.streamUrl
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func legacyState(from payload: CloudPayload) -> IptvCloudProfileState? {
        guard payload.iptvM3uUrl?.isEmpty == false || payload.iptvEpgUrl?.isEmpty == false else { return nil }
        return IptvCloudProfileState(
            m3uUrl: payload.iptvM3uUrl ?? "",
            epgUrl: payload.iptvEpgUrl ?? "",
            favoriteGroups: payload.iptvFavoriteGroups ?? [],
            favoriteChannels: payload.iptvFavoriteChannels ?? [],
            playlists: [
                IptvPlaylistEntry(
                    id: "list_1",
                    name: "List 1",
                    m3uUrl: payload.iptvM3uUrl ?? "",
                    epgUrl: payload.iptvEpgUrl ?? "",
                    enabled: true
                )
            ].filter { !$0.m3uUrl.isEmpty }
        )
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(IptvCloudProfileState.self, from: data) else {
            return
        }
        state = decoded
        selectedGroup = decoded.tvSession.lastGroupName.isEmpty ? "All" : decoded.tvSession.lastGroupName
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func attributes(from text: String) -> [String: String] {
        let pattern = #"([A-Za-z0-9_-]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var values: [String: String] = [:]
        for match in matches where match.numberOfRanges == 3 {
            values[nsText.substring(with: match.range(at: 1))] = nsText.substring(with: match.range(at: 2))
        }
        return values
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
