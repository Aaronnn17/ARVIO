import Foundation
import CryptoKit

enum HomeServerKind: String, Codable, Hashable {
    case unknown = "UNKNOWN"
    case jellyfin = "JELLYFIN"
    case emby = "EMBY"
    case plex = "PLEX"
}

struct HomeServerCollection: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var type: String = ""
    var enabled: Bool = true
}

struct HomeServerConnection: Codable, Identifiable, Hashable {
    var enabled: Bool = true
    var connectionId: String = ""
    var serverUrl: String = ""
    var displayName: String = ""
    var serverName: String = ""
    var serverKind: HomeServerKind = .unknown
    var serverId: String = ""
    var userId: String = ""
    var userName: String = ""
    var accessToken: String = ""
    var accountToken: String = ""
    var collections: [HomeServerCollection] = []
    var lastConnectedAt: Int64 = 0

    var id: String { connectionId.isEmpty ? "\(serverKind.rawValue):\(serverUrl):\(userId)" : connectionId }
    var isUsable: Bool {
        enabled && !serverUrl.isEmpty && !accessToken.isEmpty && (serverKind == .plex || !userId.isEmpty)
    }
    var displayLabel: String {
        let base = [displayName, serverName, URL(string: serverUrl)?.host, "Home Server"]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "Home Server"
        switch serverKind {
        case .plex where !base.localizedCaseInsensitiveContains("plex"): return "Plex \(base)"
        case .jellyfin where !base.localizedCaseInsensitiveContains("jellyfin"): return "Jellyfin \(base)"
        case .emby where !base.localizedCaseInsensitiveContains("emby"): return "Emby \(base)"
        default: return base
        }
    }
}

private struct HomeServerProfileConfig: Codable {
    var connections: [HomeServerConnection] = []
}

private struct ServerInfo {
    let name: String
    let id: String
    let product: String
    let kind: HomeServerKind
}

private struct HomeServerItem {
    let id: String
    let name: String
    let type: String
    let year: Int?
    let providerIds: [String: String]
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let mediaSources: [HomeServerMediaSource]
}

private struct HomeServerMediaSource {
    let id: String
    let key: String
    let name: String
    let path: String
    let container: String
    let eTag: String
    let sizeBytes: Int64
    let transcodingUrl: String
    let videoWidth: Int
    let videoHeight: Int
}

enum HomeServerService {
    static let addonId = "home_server"
    private static let clientId = "arvio-ios"

    static func parseConnections(_ json: String?) -> [HomeServerConnection] {
        guard let json = json?.trimmingCharacters(in: .whitespacesAndNewlines), !json.isEmpty,
              let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let profile = try? decoder.decode(HomeServerProfileConfig.self, from: data) {
            return sanitize(profile.connections)
        }
        if let list = try? decoder.decode([HomeServerConnection].self, from: data) {
            return sanitize(list)
        }
        if let single = try? decoder.decode(HomeServerConnection.self, from: data) {
            return sanitize([single])
        }
        return []
    }

    static func encodeConnections(_ connections: [HomeServerConnection]) -> String {
        let profile = HomeServerProfileConfig(connections: sanitize(connections))
        guard let data = try? JSONEncoder().encode(profile) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func connect(
        serverUrl rawUrl: String,
        username: String,
        secret: String,
        displayName: String
    ) async throws -> HomeServerConnection {
        let serverUrl = normalizeServerUrl(rawUrl)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverUrl.isEmpty else { throw ArvioError.invalidURL(rawUrl) }
        guard !trimmedSecret.isEmpty else { throw ArvioError.requestFailed("Enter a password or token") }

        let publicInfo = await fetchPublicInfo(serverUrl: serverUrl)
        let detectedKind = publicInfo.kind == .unknown ? detectKind(product: publicInfo.product, name: publicInfo.name) : publicInfo.kind

        if detectedKind == .plex {
            var connection = HomeServerConnection(
                enabled: true,
                connectionId: makeConnectionId(serverUrl: serverUrl, kind: .plex, user: trimmedUsername.isEmpty ? "plex" : trimmedUsername),
                serverUrl: serverUrl,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                serverName: publicInfo.name.isEmpty ? "Plex" : publicInfo.name,
                serverKind: .plex,
                serverId: publicInfo.id,
                userId: "plex",
                userName: trimmedUsername.isEmpty ? "Account" : trimmedUsername,
                accessToken: trimmedSecret,
                accountToken: trimmedSecret,
                lastConnectedAt: nowMillis()
            )
            connection.collections = try await fetchCollections(connection: connection)
            return connection
        }

        guard !trimmedUsername.isEmpty else { throw ArvioError.requestFailed("Enter a username") }
        let auth = try await authenticateJellyfin(serverUrl: serverUrl, username: trimmedUsername, password: trimmedSecret)
        var connection = HomeServerConnection(
            enabled: true,
            connectionId: makeConnectionId(serverUrl: serverUrl, kind: detectedKind, user: auth.userId.isEmpty ? trimmedUsername : auth.userId),
            serverUrl: serverUrl,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            serverName: publicInfo.name.isEmpty ? auth.serverName : publicInfo.name,
            serverKind: detectedKind,
            serverId: auth.serverId.isEmpty ? publicInfo.id : auth.serverId,
            userId: auth.userId,
            userName: auth.userName.isEmpty ? trimmedUsername : auth.userName,
            accessToken: auth.accessToken,
            accountToken: auth.accountToken,
            lastConnectedAt: nowMillis()
        )
        connection.collections = try await fetchCollections(connection: connection)
        return connection
    }

    static func testConnections(_ connections: [HomeServerConnection]) async -> [HomeServerConnection] {
        var refreshed: [HomeServerConnection] = []
        for connection in connections where connection.isUsable {
            var copy = connection
            if let collections = try? await fetchCollections(connection: connection), !collections.isEmpty {
                copy.collections = mergeCollectionStates(refreshed: collections, previous: connection.collections)
                copy.lastConnectedAt = nowMillis()
            }
            refreshed.append(copy)
        }
        return refreshed
    }

    static func catalogConfigs(from connections: [HomeServerConnection]) -> [CatalogConfig] {
        connections
            .filter(\.isUsable)
            .flatMap { connection in
                connection.collections
                    .filter { $0.enabled && !$0.id.isEmpty }
                    .map { collection in
                        CatalogConfig(
                            id: "home_server_\(stableKey("\(connection.id)|\(collection.id)"))",
                            title: catalogTitle(connection: connection, collection: collection),
                            sourceType: .homeServer,
                            sourceRef: buildCatalogSourceRef(connection: connection, collection: collection),
                            isPreinstalled: false,
                            addonId: addonId,
                            addonName: connection.displayLabel,
                            kind: .collectionRail,
                            collectionDescription: "\(connection.displayLabel) library",
                            collectionTileShape: isSeriesCollection(collection) ? .poster : .landscape
                        )
                    }
            }
    }

    static func loadCatalogItems(sourceRef: String?, settings: CloudProfileSettings) async -> [MediaItem] {
        guard let parsed = parseCatalogSourceRef(sourceRef) else { return [] }
        let connections = parseConnections(settings.homeServerConnectionJson)
        guard let connection = connections.first(where: { $0.isUsable && catalogServerKey($0) == parsed.serverKey }) else { return [] }
        let items = (try? await loadConnectionCatalogItems(
            connection: connection,
            collectionId: parsed.collectionId,
            collectionType: parsed.collectionType
        )) ?? []
        return items.compactMap { item in
            let kind: MediaKind = item.type.lowercased().contains("movie") ? .movie : .series
            let tmdbId = item.providerIds["tmdb"].flatMap { Int($0) }
            return MediaItem(
                id: "home-server-\(connection.id)-\(item.id)",
                tmdbId: tmdbId,
                title: item.name,
                subtitle: connection.displayLabel,
                year: item.year.map(String.init) ?? "",
                duration: "",
                rating: "",
                kind: kind,
                progress: 0,
                palette: ["#10202a", "#071017"],
                overview: "From \(connection.displayLabel)"
            )
        }
    }

    static func resolveSources(
        item: MediaItem,
        externalIds: TmdbExternalIds,
        season: Int,
        episode: Int,
        settings: CloudProfileSettings
    ) async -> [ResolvedStream] {
        let connections = parseConnections(settings.homeServerConnectionJson).filter(\.isUsable)
        guard !connections.isEmpty else { return [] }
        var output: [ResolvedStream] = []
        for connection in connections {
            let matched: HomeServerItem?
            if item.kind == .movie {
                matched = try? await findBestMovie(
                    connection: connection,
                    imdbId: externalIds.imdbId,
                    title: item.title,
                    year: Int(item.year),
                    tmdbId: item.tmdbId
                )
            } else {
                if let series = try? await findBestSeries(
                    connection: connection,
                    imdbId: externalIds.imdbId,
                    title: item.title,
                    tmdbId: item.tmdbId,
                    tvdbId: externalIds.tvdbId
                ) {
                    matched = try? await findEpisode(connection: connection, seriesId: series.id, season: season, episode: episode)
                } else {
                    matched = nil
                }
            }
            guard let matched else { continue }
            output.append(contentsOf: await buildStreamSources(connection: connection, item: matched, resumeSeconds: item.positionSeconds))
        }
        return output
    }

    private static func sanitize(_ connections: [HomeServerConnection]) -> [HomeServerConnection] {
        var seen = Set<String>()
        return connections.compactMap { value in
            var connection = value
            connection.serverUrl = normalizeServerUrl(connection.serverUrl)
            if connection.connectionId.isEmpty {
                connection.connectionId = makeConnectionId(serverUrl: connection.serverUrl, kind: connection.serverKind, user: connection.userId.isEmpty ? connection.userName : connection.userId)
            }
            connection.collections = connection.collections.map {
                HomeServerCollection(id: $0.id, name: $0.name, type: $0.type, enabled: $0.enabled)
            }
            guard !connection.serverUrl.isEmpty || !connection.accessToken.isEmpty else { return nil }
            guard seen.insert(connection.id).inserted else { return nil }
            return connection
        }
    }

    private static func fetchPublicInfo(serverUrl: String) async -> ServerInfo {
        if let json = try? await getJson(url: buildUrl(serverUrl, path: "/System/Info/Public"), connection: nil) {
            let name = string(json["ServerName"])
            let id = string(json["Id"])
            let product = string(json["ProductName"])
            if !name.isEmpty || !id.isEmpty || !product.isEmpty {
                return ServerInfo(name: name, id: id, product: product, kind: detectKind(product: product, name: name))
            }
        }
        if let text = try? await getText(url: buildUrl(serverUrl, path: "/identity"), connection: nil) {
            let name = xmlAttribute(text, "friendlyName")
            let id = xmlAttribute(text, "machineIdentifier")
            if !id.isEmpty || text.localizedCaseInsensitiveContains("MediaContainer") {
                return ServerInfo(name: name, id: id, product: "Media Server", kind: .plex)
            }
        }
        return ServerInfo(name: "", id: "", product: "", kind: .unknown)
    }

    private static func authenticateJellyfin(serverUrl: String, username: String, password: String) async throws -> (accessToken: String, serverId: String, serverName: String, userId: String, userName: String, accountToken: String) {
        let body: [String: Any] = ["Username": username, "Pw": password, "Password": password]
        let json = try await postJson(url: buildUrl(serverUrl, path: "/Users/AuthenticateByName"), body: body, connection: nil)
        let user = json["User"] as? [String: Any] ?? [:]
        let accessToken = string(json["AccessToken"])
        let userId = string(user["Id"])
        guard !accessToken.isEmpty, !userId.isEmpty else {
            throw ArvioError.requestFailed("Server sign in did not return a playable account")
        }
        return (
            accessToken,
            string(json["ServerId"]),
            string(user["ServerName"]),
            userId,
            string(user["Name"]),
            ""
        )
    }

    private static func fetchCollections(connection: HomeServerConnection) async throws -> [HomeServerCollection] {
        if connection.serverKind == .plex {
            let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/library/sections"), connection: connection)
            return array(json, path: ["MediaContainer", "Directory"]).compactMap { raw in
                let id = string(raw["key"])
                guard !id.isEmpty else { return nil }
                return HomeServerCollection(
                    id: id,
                    name: string(raw["title"]).nilIfBlank ?? string(raw["name"]).nilIfBlank ?? "Library \(id)",
                    type: string(raw["type"]),
                    enabled: true
                )
            }
        }
        let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/Users/\(connection.userId)/Views"), connection: connection)
        return array(json, key: "Items").compactMap { raw in
            let id = string(raw["Id"])
            guard !id.isEmpty else { return nil }
            return HomeServerCollection(
                id: id,
                name: string(raw["Name"]).nilIfBlank ?? "Library",
                type: string(raw["CollectionType"]),
                enabled: true
            )
        }
    }

    private static func loadConnectionCatalogItems(connection: HomeServerConnection, collectionId: String, collectionType: String) async throws -> [HomeServerItem] {
        if connection.serverKind == .plex {
            let components = collectionId.components(separatedBy: ":")
            let path = components.first == "collection" && components.count >= 3 ? "/library/metadata/\(components[2])/children" : "/library/sections/\(collectionId)/all"
            let plexType = plexType(for: collectionType)
            let json = try await getJson(url: buildUrl(connection.serverUrl, path: path, query: [
                "type": plexType,
                "includeGuids": "1",
                "includeMedia": "1",
                "X-Plex-Container-Start": "0",
                "X-Plex-Container-Size": "60"
            ]), connection: connection)
            return metadataItems(json, kind: .plex).compactMap { parseItem($0, kind: .plex) }
        }
        let parentId = collectionId.replacingOccurrences(of: "collection:", with: "")
        let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/Users/\(connection.userId)/Items", query: [
            "ParentId": parentId,
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Series",
            "Fields": itemFields,
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "StartIndex": "0",
            "Limit": "60"
        ]), connection: connection)
        return array(json, key: "Items").compactMap { parseItem($0, kind: connection.serverKind) }
    }

    private static func findBestMovie(connection: HomeServerConnection, imdbId: String?, title: String, year: Int?, tmdbId: Int?) async throws -> HomeServerItem? {
        let candidates = try await queryItems(connection: connection, itemTypes: "Movie", searchTerm: title, providerIds: providerQueries(imdbId: imdbId, tmdbId: tmdbId, tvdbId: nil))
        return bestCandidate(candidates, title: title, year: year, imdbId: imdbId, tmdbId: tmdbId, tvdbId: nil)
    }

    private static func findBestSeries(connection: HomeServerConnection, imdbId: String?, title: String, tmdbId: Int?, tvdbId: Int?) async throws -> HomeServerItem? {
        let candidates = try await queryItems(connection: connection, itemTypes: "Series", searchTerm: title, providerIds: providerQueries(imdbId: imdbId, tmdbId: tmdbId, tvdbId: tvdbId))
        return bestCandidate(candidates, title: title, year: nil, imdbId: imdbId, tmdbId: tmdbId, tvdbId: tvdbId)
    }

    private static func findEpisode(connection: HomeServerConnection, seriesId: String, season: Int, episode: Int) async throws -> HomeServerItem? {
        if connection.serverKind == .plex {
            let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/library/metadata/\(seriesId)/allLeaves", query: [
                "includeGuids": "1",
                "includeMedia": "1",
                "index": "\(episode)",
                "parentIndex": "\(season)"
            ]), connection: connection)
            return metadataItems(json, kind: .plex)
                .compactMap { parseItem($0, kind: .plex) }
                .first { ($0.indexNumber == episode || $0.indexNumber == nil) && ($0.parentIndexNumber == season || $0.parentIndexNumber == nil) }
        }
        let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/Shows/\(seriesId)/Episodes", query: [
            "UserId": connection.userId,
            "Season": "\(season)",
            "Fields": itemFields
        ]), connection: connection)
        return array(json, key: "Items")
            .compactMap { parseItem($0, kind: connection.serverKind) }
            .first { $0.indexNumber == episode }
    }

    private static func queryItems(connection: HomeServerConnection, itemTypes: String, searchTerm: String, providerIds: [String]) async throws -> [HomeServerItem] {
        var byId: [String: HomeServerItem] = [:]
        for providerId in providerIds {
            for item in try await queryItems(connection: connection, itemTypes: itemTypes, query: ["AnyProviderIdEquals": providerId, "Limit": "12"]) {
                byId[item.id] = item
            }
        }
        if !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for item in try await queryItems(connection: connection, itemTypes: itemTypes, query: ["SearchTerm": searchTerm, "Limit": "30"]) {
                byId[item.id] = item
            }
        }
        return Array(byId.values)
    }

    private static func queryItems(connection: HomeServerConnection, itemTypes: String, query: [String: String]) async throws -> [HomeServerItem] {
        if connection.serverKind == .plex {
            let plexType = itemTypes.lowercased().contains("movie") ? "1" : "2"
            let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/search", query: [
                "query": query["SearchTerm"] ?? query["AnyProviderIdEquals"] ?? "",
                "type": plexType,
                "includeGuids": "1",
                "includeMedia": "1",
                "limit": query["Limit"] ?? "30"
            ]), connection: connection)
            return metadataItems(json, kind: .plex).compactMap { parseItem($0, kind: .plex) }
        }
        var merged = query
        merged["Recursive"] = "true"
        merged["IncludeItemTypes"] = itemTypes
        merged["Fields"] = itemFields
        let json = try await getJson(url: buildUrl(connection.serverUrl, path: "/Users/\(connection.userId)/Items", query: merged), connection: connection)
        return array(json, key: "Items").compactMap { parseItem($0, kind: connection.serverKind) }
    }

    private static func buildStreamSources(connection: HomeServerConnection, item: HomeServerItem, resumeSeconds: Int?) async -> [ResolvedStream] {
        let sources: [HomeServerMediaSource]
        if connection.serverKind == .plex,
           let refreshed = try? await getJson(url: buildUrl(connection.serverUrl, path: "/library/metadata/\(item.id)", query: ["includeMedia": "1"]), connection: connection) {
            sources = (metadataItems(refreshed, kind: .plex).compactMap { parseItem($0, kind: .plex) }.first?.mediaSources ?? []) + item.mediaSources
        } else if connection.serverKind != .plex,
                  let info = try? await postJson(url: buildUrl(connection.serverUrl, path: "/Items/\(item.id)/PlaybackInfo", query: [
                    "UserId": connection.userId,
                    "StartTimeTicks": "0",
                    "IsPlayback": "true",
                    "AutoOpenLiveStream": "true",
                    "MaxStreamingBitrate": "2147483647"
                  ]), body: [:], connection: connection) {
            sources = parseMediaSources(info, kind: connection.serverKind) + item.mediaSources
        } else {
            sources = item.mediaSources
        }

        var seen = Set<String>()
        return sources.compactMap { source in
            guard let url = playbackUrl(connection: connection, itemId: item.id, source: source),
                  let parsedUrl = URL(string: url) else { return nil }
            let quality = qualityLabel(source)
            let id = "\(url)|\(source.name)"
            guard seen.insert(id).inserted else { return nil }
            return ResolvedStream(
                addonId: addonId,
                addonName: connection.displayLabel,
                sourceName: [connection.displayLabel, quality, source.container.uppercased()].filter { !$0.isEmpty }.joined(separator: " "),
                title: source.name.isEmpty ? item.name : source.name,
                quality: quality.isEmpty ? "Unknown" : quality,
                size: formatBytes(source.sizeBytes),
                url: parsedUrl,
                requestHeaders: playbackHeaders(connection),
                subtitles: [],
                isPlayable: true,
                resumePositionSeconds: resumeSeconds
            )
        }
        .sorted { qualityRank($0.quality) > qualityRank($1.quality) }
    }

    private static func parseItem(_ json: [String: Any], kind: HomeServerKind) -> HomeServerItem? {
        if kind == .plex {
            let id = string(json["ratingKey"]).nilIfBlank ?? string(json["key"])
            guard !id.isEmpty else { return nil }
            let providers = array(json, key: "Guid").reduce(into: [String: String]()) { partial, raw in
                let guid = string(raw["id"])
                let pieces = guid.components(separatedBy: "://")
                guard pieces.count == 2 else { return }
                partial[pieces[0].lowercased()] = pieces[1].components(separatedBy: "?").first ?? ""
            }
            let media = array(json, key: "Media")
            let sources = media.flatMap { mediaObject in
                array(mediaObject, key: "Part").map { part in
                    parseMediaSource(part, kind: .plex, parent: mediaObject)
                }
            }
            return HomeServerItem(
                id: id,
                name: string(json["title"]),
                type: string(json["type"]),
                year: int(json["year"]) ?? Int(String(string(json["originallyAvailableAt"]).prefix(4))),
                providerIds: providers,
                indexNumber: int(json["index"]),
                parentIndexNumber: int(json["parentIndex"]),
                mediaSources: sources
            )
        }
        let providerIds = (json["ProviderIds"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) {
            $0[$1.key.lowercased()] = string($1.value)
        }
        let id = string(json["Id"])
        guard !id.isEmpty else { return nil }
        return HomeServerItem(
            id: id,
            name: string(json["Name"]),
            type: string(json["Type"]),
                year: int(json["ProductionYear"]) ?? Int(String(string(json["PremiereDate"]).prefix(4))),
            providerIds: providerIds,
            indexNumber: int(json["IndexNumber"]),
            parentIndexNumber: int(json["ParentIndexNumber"]),
            mediaSources: parseMediaSources(json, kind: kind)
        )
    }

    private static func parseMediaSources(_ json: [String: Any], kind: HomeServerKind) -> [HomeServerMediaSource] {
        array(json, key: "MediaSources").map { parseMediaSource($0, kind: kind, parent: nil) }
    }

    private static func parseMediaSource(_ json: [String: Any], kind: HomeServerKind, parent: [String: Any]?) -> HomeServerMediaSource {
        if kind == .plex {
            return HomeServerMediaSource(
                id: string(json["id"]),
                key: string(json["key"]),
                name: string(json["file"]).components(separatedBy: "/").last ?? string(parent?["title"] ?? nil),
                path: string(json["file"]),
                container: string(parent?["container"] ?? nil).nilIfBlank ?? string(json["container"]),
                eTag: "",
                sizeBytes: int64(json["size"]) ?? 0,
                transcodingUrl: "",
                videoWidth: int(parent?["width"]) ?? int(json["width"]) ?? 0,
                videoHeight: int(parent?["height"]) ?? int(json["height"]) ?? 0
            )
        }
        let streams = array(json, key: "MediaStreams")
        let video = streams.first { string($0["Type"]).caseInsensitiveCompare("Video") == .orderedSame }
        return HomeServerMediaSource(
            id: string(json["Id"]),
            key: "",
            name: string(json["Name"]),
            path: string(json["Path"]),
            container: string(json["Container"]),
            eTag: string(json["ETag"]).nilIfBlank ?? string(json["Etag"]),
            sizeBytes: int64(json["Size"]) ?? 0,
            transcodingUrl: string(json["TranscodingUrl"]),
            videoWidth: int(video?["Width"]) ?? 0,
            videoHeight: int(video?["Height"]) ?? 0
        )
    }

    private static func playbackUrl(connection: HomeServerConnection, itemId: String, source: HomeServerMediaSource) -> String? {
        if connection.serverKind == .plex {
            if !source.key.isEmpty { return appendQuery(absoluteUrl(base: connection.serverUrl, pathOrUrl: source.key), ["X-Plex-Token": connection.accessToken]) }
            if source.path.lowercased().hasPrefix("http") { return appendQuery(source.path, ["X-Plex-Token": connection.accessToken]) }
            if !source.id.isEmpty { return buildUrl(connection.serverUrl, path: "/library/parts/\(source.id)/file", query: ["X-Plex-Token": connection.accessToken]) }
            return nil
        }
        if source.path.lowercased().hasPrefix("http") { return source.path }
        if !source.transcodingUrl.isEmpty {
            return appendQuery(absoluteUrl(base: connection.serverUrl, pathOrUrl: source.transcodingUrl), ["api_key": connection.accessToken])
        }
        let ext = source.container.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "matroska", with: "mkv")
        let streamPath = ext?.isEmpty == false ? "/Videos/\(itemId)/stream.\(ext!)" : "/Videos/\(itemId)/stream"
        return buildUrl(connection.serverUrl, path: streamPath, query: [
            "Static": "true",
            "MediaSourceId": source.id,
            "DeviceId": clientId,
            "api_key": connection.accessToken,
            "Tag": source.eTag
        ])
    }

    private static func getJson(url: String, connection: HomeServerConnection?) async throws -> [String: Any] {
        let data = try await request(url: url, method: "GET", body: nil, connection: connection)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func getText(url: String, connection: HomeServerConnection?) async throws -> String {
        let data = try await request(url: url, method: "GET", body: nil, connection: connection)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func postJson(url: String, body: [String: Any], connection: HomeServerConnection?) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await request(url: url, method: "POST", body: data, connection: connection)
        return (try JSONSerialization.jsonObject(with: response) as? [String: Any]) ?? [:]
    }

    private static func request(url rawUrl: String, method: String, body: Data?, connection: HomeServerConnection?) async throws -> Data {
        guard let url = URL(string: rawUrl) else { throw ArvioError.invalidURL(rawUrl) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ARVIO/0.1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let connection {
            for (key, value) in playbackHeaders(connection) {
                request.setValue(value, forHTTPHeaderField: key)
            }
        } else {
            request.setValue(jellyfinAuthorization(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Server request failed")
        }
        return data
    }

    private static func playbackHeaders(_ connection: HomeServerConnection) -> [String: String] {
        if connection.serverKind == .plex {
            return [
                "Accept": "application/json",
                "User-Agent": "ARVIO/0.1.0",
                "X-Plex-Client-Identifier": clientId,
                "X-Plex-Product": "ARVIO",
                "X-Plex-Version": "0.1.0",
                "X-Plex-Device": "iOS",
                "X-Plex-Platform": "iOS",
                "X-Plex-Token": connection.accessToken
            ]
        }
        return [
            "User-Agent": "ARVIO/0.1.0",
            "X-Emby-Authorization": jellyfinAuthorization(token: connection.accessToken),
            "X-Emby-Token": connection.accessToken
        ]
    }

    private static func jellyfinAuthorization(token: String?) -> String {
        let base = "MediaBrowser Client=\"ARVIO\", Device=\"iOS\", DeviceId=\"\(clientId)\", Version=\"0.1.0\""
        guard let token, !token.isEmpty else { return base }
        return "\(base), Token=\"\(token)\""
    }

    private static func buildUrl(_ baseUrl: String, path: String, query: [String: String?] = [:]) -> String {
        guard var components = URLComponents(string: baseUrl) else { return baseUrl + path }
        var pathValue = components.path
        if pathValue.hasSuffix("/") { pathValue.removeLast() }
        components.path = pathValue + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.queryItems = query.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        return components.url?.absoluteString ?? baseUrl + path
    }

    private static func normalizeServerUrl(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty else { return "" }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") { return value }
        return "http://\(value)"
    }

    private static func absoluteUrl(base: String, pathOrUrl: String) -> String {
        if pathOrUrl.lowercased().hasPrefix("http://") || pathOrUrl.lowercased().hasPrefix("https://") { return pathOrUrl }
        return buildUrl(base, path: pathOrUrl)
    }

    private static func appendQuery(_ raw: String, _ query: [String: String]) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        var items = components.queryItems ?? []
        for (key, value) in query where !items.contains(where: { $0.name == key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url?.absoluteString ?? raw
    }

    private static func providerQueries(imdbId: String?, tmdbId: Int?, tvdbId: Int?) -> [String] {
        var values: [String] = []
        if let imdbId, !imdbId.isEmpty { values.append("imdb.\(imdbId)") }
        if let tmdbId { values.append("tmdb.\(tmdbId)") }
        if let tvdbId { values.append("tvdb.\(tvdbId)") }
        return values
    }

    private static func bestCandidate(_ candidates: [HomeServerItem], title: String, year: Int?, imdbId: String?, tmdbId: Int?, tvdbId: Int?) -> HomeServerItem? {
        candidates
            .map { ($0, score(item: $0, title: title, year: year, imdbId: imdbId, tmdbId: tmdbId, tvdbId: tvdbId)) }
            .filter { $0.1 >= 120 || $0.1 >= 900 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func score(item: HomeServerItem, title: String, year: Int?, imdbId: String?, tmdbId: Int?, tvdbId: Int?) -> Int {
        var value = 0
        let providers = item.providerIds
        if let imdbId, providers["imdb"]?.lowercased() == imdbId.lowercased() { value += 1000 }
        if let tmdbId, providers["tmdb"].flatMap({ Int($0) }) == tmdbId { value += 900 }
        if let tvdbId, providers["tvdb"].flatMap({ Int($0) }) == tvdbId { value += 900 }
        let wanted = normalizeTitle(title)
        let found = normalizeTitle(item.name)
        if wanted == found, !wanted.isEmpty { value += 140 }
        if !wanted.isEmpty && !found.isEmpty && (wanted.contains(found) || found.contains(wanted)) { value += 65 }
        if let year, let itemYear = item.year {
            let delta = abs(year - itemYear)
            if delta == 0 { value += 90 } else if delta == 1 { value += 45 } else if delta <= 2 { value += 15 } else { value -= 120 }
        }
        return value
    }

    private static func normalizeTitle(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(the|a|an)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func metadataItems(_ json: [String: Any], kind: HomeServerKind) -> [[String: Any]] {
        let values = array(json, path: ["MediaContainer", "Metadata"])
        if !values.isEmpty { return values }
        return array(json, key: "Metadata")
    }

    private static func array(_ json: [String: Any], key: String) -> [[String: Any]] {
        json[key] as? [[String: Any]] ?? []
    }

    private static func array(_ json: [String: Any], path: [String]) -> [[String: Any]] {
        var current: Any? = json
        for segment in path {
            current = (current as? [String: Any])?[segment]
        }
        return current as? [[String: Any]] ?? []
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func detectKind(product: String, name: String) -> HomeServerKind {
        let value = "\(product) \(name)".lowercased()
        if value.contains("plex") || value.contains("media server") { return .plex }
        if value.contains("emby") { return .emby }
        if value.contains("jellyfin") { return .jellyfin }
        return .jellyfin
    }

    private static func plexType(for collectionType: String) -> String? {
        let value = collectionType.lowercased()
        if value.contains("movie") { return "1" }
        if value.contains("series") || value.contains("show") || value.contains("tv") { return "2" }
        return nil
    }

    private static var itemFields: String { "ProviderIds,MediaSources,MediaStreams,Path,PremiereDate,ProductionYear,RunTimeTicks" }

    private static func qualityLabel(_ source: HomeServerMediaSource) -> String {
        if source.videoHeight >= 2160 || source.videoWidth >= 3800 { return "4K" }
        if source.videoHeight >= 1440 { return "1440p" }
        if source.videoHeight >= 1080 { return "1080p" }
        if source.videoHeight >= 720 { return "720p" }
        if source.videoHeight >= 576 { return "576p" }
        if source.videoHeight >= 480 { return "480p" }
        return StreamQualityExtractor.quality(from: source.name)
    }

    private static func qualityRank(_ quality: String) -> Int {
        let value = quality.lowercased()
        if value.contains("4k") || value.contains("2160") { return 2160 }
        if value.contains("1440") { return 1440 }
        if value.contains("1080") { return 1080 }
        if value.contains("720") { return 720 }
        if value.contains("576") { return 576 }
        if value.contains("480") { return 480 }
        return 0
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    private static func catalogServerKey(_ connection: HomeServerConnection) -> String {
        if !connection.serverId.isEmpty { return connection.serverId }
        if !connection.connectionId.isEmpty { return connection.connectionId }
        return "\(connection.serverKind.rawValue):\(connection.serverUrl)"
    }

    private static func buildCatalogSourceRef(connection: HomeServerConnection, collection: HomeServerCollection) -> String {
        [
            "home_server_catalog",
            catalogServerKey(connection),
            collection.id,
            collection.type
        ]
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
            .joined(separator: "|")
    }

    private static func parseCatalogSourceRef(_ sourceRef: String?) -> (serverKey: String, collectionId: String, collectionType: String)? {
        let parts = (sourceRef ?? "").components(separatedBy: "|")
        guard parts.count >= 3, parts[0] == "home_server_catalog" else { return nil }
        let serverKey = parts[1].removingPercentEncoding ?? parts[1]
        let collectionId = parts[2].removingPercentEncoding ?? parts[2]
        let collectionType = parts.count > 3 ? (parts[3].removingPercentEncoding ?? parts[3]) : ""
        guard !serverKey.isEmpty, !collectionId.isEmpty else { return nil }
        return (serverKey, collectionId, collectionType)
    }

    private static func catalogTitle(connection: HomeServerConnection, collection: HomeServerCollection) -> String {
        let server = connection.displayLabel
        if collection.name.localizedCaseInsensitiveContains(server) { return collection.name }
        return "\(server) - \(collection.name.isEmpty ? "Library" : collection.name)"
    }

    private static func isSeriesCollection(_ collection: HomeServerCollection) -> Bool {
        let value = "\(collection.name) \(collection.type)".lowercased()
        return value.contains("series") || value.contains("show") || value.contains("tv")
    }

    private static func mergeCollectionStates(refreshed: [HomeServerCollection], previous: [HomeServerCollection]) -> [HomeServerCollection] {
        let previousById = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return refreshed.map { collection in
            var updated = collection
            updated.enabled = previousById[collection.id]?.enabled ?? collection.enabled
            return updated
        }
    }

    private static func makeConnectionId(serverUrl: String, kind: HomeServerKind, user: String) -> String {
        "\(kind.rawValue):\(serverUrl.lowercased()):\(user.lowercased())"
            .replacingOccurrences(of: "[^a-z0-9:._-]+", with: "_", options: .regularExpression)
    }

    private static func stableKey(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func xmlAttribute(_ text: String, _ name: String) -> String {
        let pattern = #"\b\#(name)=["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private enum StreamQualityExtractor {
    static func quality(from text: String) -> String {
        if text.range(of: "2160|4K|UHD", options: [.regularExpression, .caseInsensitive]) != nil { return "4K" }
        if text.range(of: "1440", options: [.regularExpression, .caseInsensitive]) != nil { return "1440p" }
        if text.range(of: "1080", options: [.regularExpression, .caseInsensitive]) != nil { return "1080p" }
        if text.range(of: "720", options: [.regularExpression, .caseInsensitive]) != nil { return "720p" }
        if text.range(of: "480", options: [.regularExpression, .caseInsensitive]) != nil { return "480p" }
        return ""
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
