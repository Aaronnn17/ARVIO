import Foundation
import CryptoKit

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
    var stalkerPortalUrl: String = ""
    var stalkerMacAddress: String = ""
    var favoriteGroups: [String] = []
    var favoriteChannels: [String] = []
    var hiddenGroups: [String] = []
    var groupOrder: [String] = []
    var playlists: [IptvPlaylistEntry] = []
    var tvSession: IptvTvSessionState = IptvTvSessionState()

    enum CodingKeys: String, CodingKey {
        case m3uUrl
        case epgUrl
        case stalkerPortalUrl
        case stalkerMacAddress
        case favoriteGroups
        case favoriteChannels
        case hiddenGroups
        case groupOrder
        case playlists
        case tvSession
    }

    init() {}

    init(
        m3uUrl: String = "",
        epgUrl: String = "",
        stalkerPortalUrl: String = "",
        stalkerMacAddress: String = "",
        favoriteGroups: [String] = [],
        favoriteChannels: [String] = [],
        hiddenGroups: [String] = [],
        groupOrder: [String] = [],
        playlists: [IptvPlaylistEntry] = [],
        tvSession: IptvTvSessionState = IptvTvSessionState()
    ) {
        self.m3uUrl = m3uUrl
        self.epgUrl = epgUrl
        self.stalkerPortalUrl = stalkerPortalUrl
        self.stalkerMacAddress = stalkerMacAddress
        self.favoriteGroups = favoriteGroups
        self.favoriteChannels = favoriteChannels
        self.hiddenGroups = hiddenGroups
        self.groupOrder = groupOrder
        self.playlists = playlists
        self.tvSession = tvSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        m3uUrl = (try? container.decode(String.self, forKey: .m3uUrl)) ?? ""
        epgUrl = (try? container.decode(String.self, forKey: .epgUrl)) ?? ""
        stalkerPortalUrl = (try? container.decode(String.self, forKey: .stalkerPortalUrl)) ?? ""
        stalkerMacAddress = (try? container.decode(String.self, forKey: .stalkerMacAddress)) ?? ""
        favoriteGroups = (try? container.decode([String].self, forKey: .favoriteGroups)) ?? []
        favoriteChannels = (try? container.decode([String].self, forKey: .favoriteChannels)) ?? []
        hiddenGroups = (try? container.decode([String].self, forKey: .hiddenGroups)) ?? []
        groupOrder = (try? container.decode([String].self, forKey: .groupOrder)) ?? []
        playlists = (try? container.decode([IptvPlaylistEntry].self, forKey: .playlists)) ?? []
        tvSession = (try? container.decode(IptvTvSessionState.self, forKey: .tvSession)) ?? IptvTvSessionState()
    }
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

struct IptvProgram: Identifiable, Hashable {
    let id: String
    let channelKey: String
    let title: String
    let description: String
    let start: Date
    let stop: Date
}

struct IptvNowNext: Hashable {
    let now: IptvProgram?
    let next: IptvProgram?
}

@MainActor
final class IptvService: ObservableObject {
    @Published private(set) var state = IptvCloudProfileState()
    @Published private(set) var channels: [IptvChannel] = []
    @Published private(set) var nowNextByChannelId: [String: IptvNowNext] = [:]
    @Published private(set) var programsByChannelId: [String: [IptvProgram]] = [:]
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
        let hidden = Set(state.hiddenGroups)
        let unique = Array(Set(rawGroups))
            .filter { !hidden.contains($0) }
            .sorted { left, right in
                let leftIndex = state.groupOrder.firstIndex(of: left)
                let rightIndex = state.groupOrder.firstIndex(of: right)
                switch (leftIndex, rightIndex) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                }
            }
        let favoriteGroups = state.favoriteGroups.filter { unique.contains($0) }
        return ["All", "Favorites"] + favoriteGroups + unique.filter { !favoriteGroups.contains($0) }
    }

    var visibleChannels: [IptvChannel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return channels.filter { channel in
            let groupMatches = selectedGroup == "All" ||
                (selectedGroup == "Favorites" && state.favoriteChannels.contains(channel.id)) ||
                (selectedGroup == "Favorites" && state.favoriteGroups.contains(channel.group)) ||
                channel.group == selectedGroup
            let hiddenMatches = selectedGroup != "All" || !state.hiddenGroups.contains(channel.group)
            let searchMatches = query.isEmpty || channel.name.localizedCaseInsensitiveContains(query)
            return groupMatches && hiddenMatches && searchMatches
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

    func saveStalkerConfig(portalUrl: String, macAddress: String) async {
        state.stalkerPortalUrl = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        state.stalkerMacAddress = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        saveLocal()
        await cloud.save(iptv: state, profileId: activeProfileId)
        await reload()
    }

    func reload() async {
        let playlists = activePlaylists()
        let hasStalker = !state.stalkerPortalUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !state.stalkerMacAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !playlists.isEmpty || hasStalker else {
            errorMessage = "Add an M3U, Xtream, or Stalker provider to load Live TV"
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
            if hasStalker {
                loaded.append(contentsOf: try await StalkerClient(
                    portalUrl: state.stalkerPortalUrl,
                    macAddress: state.stalkerMacAddress
                ).loadChannels())
            }
            channels = deduplicate(loaded)
            let guide = try await loadGuide(for: channels, playlists: playlists)
            nowNextByChannelId = guide.nowNext
            programsByChannelId = guide.programs
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

    func toggleFavoriteGroup(_ group: String) async {
        guard group != "All", group != "Favorites" else { return }
        if state.favoriteGroups.contains(group) {
            state.favoriteGroups.removeAll { $0 == group }
        } else {
            state.favoriteGroups.append(group)
        }
        saveLocal()
        await cloud.save(iptv: state, profileId: activeProfileId)
    }

    func toggleHiddenGroup(_ group: String) async {
        guard group != "All", group != "Favorites" else { return }
        if state.hiddenGroups.contains(group) {
            state.hiddenGroups.removeAll { $0 == group }
        } else {
            state.hiddenGroups.append(group)
            state.favoriteGroups.removeAll { $0 == group }
            if selectedGroup == group { selectedGroup = "All" }
        }
        saveLocal()
        await cloud.save(iptv: state, profileId: activeProfileId)
    }

    func moveGroup(_ group: String, direction: Int) async {
        guard group != "All", group != "Favorites" else { return }
        var order = state.groupOrder
        let visible = Array(Set(channels.map { $0.group.isEmpty ? "Uncategorized" : $0.group })).sorted()
        for value in visible where !order.contains(value) {
            order.append(value)
        }
        guard let index = order.firstIndex(of: group) else { return }
        let nextIndex = max(0, min(order.count - 1, index + direction))
        guard index != nextIndex else { return }
        order.swapAt(index, nextIndex)
        state.groupOrder = order
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
        if let credentials = XtreamCredentials.from(urlString: playlist.m3uUrl) {
            return try await fetchXtreamLiveChannels(credentials: credentials)
        }
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

    private func fetchXtreamLiveChannels(credentials: XtreamCredentials) async throws -> [IptvChannel] {
        progressMessage = "Loading Xtream channels..."
        guard var components = URLComponents(string: credentials.baseUrl + "/player_api.php") else {
            throw ArvioError.invalidURL(credentials.baseUrl)
        }
        components.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "action", value: "get_live_streams")
        ]
        guard let url = components.url else { throw ArvioError.invalidURL(credentials.baseUrl) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Xtream channels failed to load")
        }
        let streams = try JSONDecoder().decode([XtreamLiveStream].self, from: data)
        return streams.compactMap { stream -> IptvChannel? in
            guard let streamId = stream.streamId else { return nil }
            let streamUrl = "\(credentials.baseUrl)/live/\(credentials.username)/\(credentials.password)/\(streamId).ts"
            return IptvChannel(
                id: stableChannelId(epgId: stream.epgChannelId, streamUrl: streamUrl),
                name: stream.name.nilIfBlank ?? "Channel \(streamId)",
                streamUrl: streamUrl,
                group: stream.categoryName?.nilIfBlank ?? stream.categoryId.map { "Category \($0)" } ?? "Xtream",
                logo: stream.streamIcon?.nilIfBlank,
                epgId: stream.epgChannelId?.nilIfBlank,
                rawTitle: stream.name
            )
        }
    }

    private func loadGuide(for channels: [IptvChannel], playlists: [IptvPlaylistEntry]) async throws -> (nowNext: [String: IptvNowNext], programs: [String: [IptvProgram]]) {
        let epgUrls = Array(Set(playlists.flatMap { playlist -> [String] in
            let configured = playlist.epgUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !configured.isEmpty { return [configured] }
            if let credentials = XtreamCredentials.from(urlString: playlist.m3uUrl) {
                return ["\(credentials.baseUrl)/xmltv.php?username=\(credentials.username)&password=\(credentials.password)"]
            }
            return []
        }))
        guard !epgUrls.isEmpty, !channels.isEmpty else { return ([:], [:]) }
        progressMessage = "Loading guide..."

        var programs: [IptvProgram] = []
        for rawUrl in epgUrls {
            guard let url = URL(string: rawUrl) else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
            programs.append(contentsOf: XMLTVParser.parse(data: data))
        }

        let now = Date()
        var channelLookup: [String: String] = [:]
        for channel in channels {
            channelLookup[channel.name.normalizedGuideKey] = channel.id
            if let epgId = channel.epgId?.nilIfBlank {
                channelLookup[epgId.normalizedGuideKey] = channel.id
            }
        }

        var grouped: [String: [IptvProgram]] = [:]
        for program in programs {
            guard let channelId = channelLookup[program.channelKey.normalizedGuideKey] else { continue }
            grouped[channelId, default: []].append(program)
        }

        var result: [String: IptvNowNext] = [:]
        for (channelId, values) in grouped {
            let sorted = values.sorted { $0.start < $1.start }
            let current = sorted.last { $0.start <= now && $0.stop > now }
            let next = sorted.first { $0.start > now }
            if current != nil || next != nil {
                result[channelId] = IptvNowNext(now: current, next: next)
            }
        }
        return (result, grouped.mapValues { $0.sorted { $0.start < $1.start } })
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
                        id: stableChannelId(epgId: meta.epgId, streamUrl: line),
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

    private func stableChannelId(epgId: String?, streamUrl: String) -> String {
        let normalizedEpg = epgId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let streamKey = stableStreamKey(streamUrl)
        return normalizedEpg.isEmpty ? "m3u:\(streamKey)" : "m3u:\(normalizedEpg):\(streamKey)"
    }

    private func stableStreamKey(_ streamUrl: String) -> String {
        let normalized = streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "empty" }
        let digest = Insecure.SHA1.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(normalized.count)-\(String(digest.prefix(16)))"
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

    var normalizedGuideKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct XtreamCredentials {
    let baseUrl: String
    let username: String
    let password: String

    static func from(urlString: String) -> XtreamCredentials? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name.lowercased(), $0) }
        })
        guard let username = query["username"]?.nilIfBlank,
              let password = query["password"]?.nilIfBlank else {
            return nil
        }
        let port = components.port.map { ":\($0)" } ?? ""
        return XtreamCredentials(baseUrl: "\(scheme)://\(host)\(port)", username: username, password: password)
    }
}

private struct XtreamLiveStream: Decodable {
    let name: String
    let streamId: Int?
    let streamIcon: String?
    let epgChannelId: String?
    let categoryId: Int?
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Channel"
        streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        epgChannelId = try? container.decode(String.self, forKey: .epgChannelId)
        categoryName = try? container.decode(String.self, forKey: .categoryName)
        if let intValue = try? container.decode(Int.self, forKey: .streamId) {
            streamId = intValue
        } else {
            streamId = Int((try? container.decode(String.self, forKey: .streamId)) ?? "")
        }
        if let intValue = try? container.decode(Int.self, forKey: .categoryId) {
            categoryId = intValue
        } else {
            categoryId = Int((try? container.decode(String.self, forKey: .categoryId)) ?? "")
        }
    }
}

private final class StalkerClient {
    private let portalUrl: String
    private let macAddress: String
    private var token = ""

    init(portalUrl: String, macAddress: String) {
        self.portalUrl = portalUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.macAddress = macAddress
    }

    func loadChannels() async throws -> [IptvChannel] {
        token = try await handshake()
        let genres = try await getGenres()
        let rawChannels = try await getChannels()
        return rawChannels.compactMap { channel -> IptvChannel? in
            let command = channel["cmd"] as? String ?? channel["streamUrl"] as? String ?? ""
            guard !command.isEmpty else { return nil }
            let streamUrl = resolveStreamCommand(command)
            let id = String(describing: channel["id"] ?? channel["ch_id"] ?? channel["name"] ?? streamUrl)
            let groupId = String(describing: channel["tv_genre_id"] ?? channel["category_id"] ?? "")
            let group = genres[groupId] ?? "Stalker"
            let name = (channel["name"] as? String)?.nilIfBlank ?? "Channel \(id)"
            return IptvChannel(
                id: Self.stableChannelId(epgId: id, streamUrl: streamUrl),
                name: name,
                streamUrl: streamUrl,
                group: group,
                logo: (channel["logo"] as? String)?.nilIfBlank,
                epgId: id,
                rawTitle: name
            )
        }
    }

    private func handshake() async throws -> String {
        let object = try await request(action: "handshake", type: "stb")
        guard let token = (object["js"] as? [String: Any])?["token"] as? String, !token.isEmpty else {
            throw ArvioError.requestFailed("Stalker handshake failed")
        }
        return token
    }

    private func getGenres() async throws -> [String: String] {
        let object = try await request(action: "get_genres", type: "itv")
        guard let values = object["js"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for value in values {
            let id = String(describing: value["id"] ?? "")
            if let title = value["title"] as? String, !id.isEmpty {
                result[id] = title
            }
        }
        return result
    }

    private func getChannels() async throws -> [[String: Any]] {
        let object = try await request(action: "get_all_channels", type: "itv")
        if let data = ((object["js"] as? [String: Any])?["data"] as? [[String: Any]]) {
            return data
        }
        if let data = object["js"] as? [[String: Any]] {
            return data
        }
        return []
    }

    private func request(action: String, type: String) async throws -> [String: Any] {
        guard var components = URLComponents(string: "\(portalUrl)/portal.php") else {
            throw ArvioError.invalidURL(portalUrl)
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "JsHttpRequest", value: "1-xml")
        ]
        guard let url = components.url else { throw ArvioError.invalidURL(portalUrl) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (QtEmbedded; U; Linux; C) MAG250", forHTTPHeaderField: "User-Agent")
        request.setValue("mac=\(macAddress); stb_lang=en; timezone=Europe/Amsterdam", forHTTPHeaderField: "Cookie")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Stalker request failed")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArvioError.decodingFailed
        }
        return object
    }

    private func resolveStreamCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http") { return trimmed }
        if let range = trimmed.range(of: "http") {
            return String(trimmed[range.lowerBound...])
        }
        return trimmed
    }

    private static func stableChannelId(epgId: String?, streamUrl: String) -> String {
        let normalizedEpg = epgId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalized = streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = Insecure.SHA1.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let key = "\(normalized.count)-\(String(digest.prefix(16)))"
        return normalizedEpg.isEmpty ? "m3u:\(key)" : "m3u:\(normalizedEpg):\(key)"
    }
}

private final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programs: [IptvProgram] = []
    private var currentChannel = ""
    private var currentStart: Date?
    private var currentStop: Date?
    private var currentTitle = ""
    private var currentDescription = ""
    private var activeElement = ""
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        return formatter
    }()

    static func parse(data: Data) -> [IptvProgram] {
        let delegate = XMLTVParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.programs
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        activeElement = elementName
        if elementName == "programme" {
            currentChannel = attributeDict["channel"] ?? ""
            currentStart = Self.parseDate(attributeDict["start"])
            currentStop = Self.parseDate(attributeDict["stop"])
            currentTitle = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeElement == "title" {
            currentTitle += string
        } else if activeElement == "desc" {
            currentDescription += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "programme",
           let start = currentStart,
           let stop = currentStop,
           !currentChannel.isEmpty,
           !currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            programs.append(
                IptvProgram(
                    id: "\(currentChannel)-\(start.timeIntervalSince1970)",
                    channelKey: currentChannel,
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: start,
                    stop: stop
                )
            )
        }
        activeElement = ""
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = formatter.date(from: normalized) {
            return date
        }
        let compact = String(normalized.prefix(14)) + " +0000"
        return formatter.date(from: compact)
    }
}
