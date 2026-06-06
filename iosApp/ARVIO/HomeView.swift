import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let hero = appState.watchHistory.continueWatching.first ?? appState.catalogs.rows.first?.items.first ?? appState.tmdb.trendingMovies.first {
                    HeroSection(item: hero)
                } else {
                    BrandHeroSection()
                }
                if !appState.watchHistory.continueWatching.isEmpty {
                    MediaRail(
                        title: "Continue Watching",
                        items: appState.watchHistory.continueWatching,
                        onRemove: { item in
                            Task { await appState.watchHistory.dismiss(item) }
                        }
                    )
                }
                if !favoriteChannels.isEmpty {
                    LiveChannelRail(title: "Favorite Channels", channels: favoriteChannels)
                }
                ForEach(collectionRails) { rail in
                    let collections = collectionCatalogs(for: rail)
                    if !collections.isEmpty {
                        CollectionCatalogRail(title: rail.title, collections: collections)
                    }
                }
                if appState.catalogs.isLoading && appState.catalogs.rows.isEmpty {
                    EmptyStatePanel(title: "Loading catalogs", message: "Syncing your Android catalog rows from ARVIO cloud.")
                }
                ForEach(appState.catalogs.rows) { row in
                    MediaRail(title: row.config.title, items: row.items, catalog: row.config)
                }
                if appState.catalogs.rows.isEmpty {
                    MediaRail(title: "Trending Movies", items: appState.tmdb.trendingMovies)
                    MediaRail(title: "Trending Series", items: appState.tmdb.trendingSeries)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .refreshable {
            await appState.watchHistory.load()
            await loadLiveTVIfNeeded()
            await appState.catalogs.reloadRows()
        }
        .task {
            await loadLiveTVIfNeeded()
        }
    }

    private var favoriteChannels: [IptvChannel] {
        appState.iptv.channels.filter { channel in
            appState.iptv.state.favoriteChannels.contains(channel.id) ||
                appState.iptv.state.favoriteGroups.contains(channel.group)
        }
    }

    private var collectionRails: [CatalogConfig] {
        appState.catalogs.catalogs.filter { $0.kind == .collectionRail }
    }

    private func collectionCatalogs(for rail: CatalogConfig) -> [CatalogConfig] {
        appState.catalogs.catalogs.filter { catalog in
            catalog.kind == .collection &&
                catalog.collectionGroup == rail.collectionGroup
        }
    }

    private func loadLiveTVIfNeeded() async {
        guard appState.iptv.channels.isEmpty else { return }
        guard !appState.iptv.state.m3uUrl.isEmpty ||
            !appState.iptv.state.stalkerPortalUrl.isEmpty ||
            !appState.iptv.state.playlists.isEmpty else { return }
        await appState.iptv.reload()
    }
}

struct CollectionCatalogRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let collections: [CatalogConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(collections) { collection in
                        Button {
                            appState.selectedCatalog = collection
                        } label: {
                            CollectionCatalogCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct CollectionCatalogCard: View {
    let collection: CatalogConfig

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [ArvioTheme.panel, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(colors: [.clear, Color.black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            if !collection.collectionHideTitle {
                Text(collection.title)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(2)
                    .padding(14)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private var coverURL: URL? {
        [collection.collectionCoverImageUrl, collection.collectionHeroImageUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap(URL.init(string:))
    }

    private var width: CGFloat {
        collection.collectionTileShape == .poster ? 150 : 260
    }

    private var height: CGFloat {
        collection.collectionTileShape == .poster ? 225 : 146
    }
}

struct BrandHeroSection: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("ARVIOTVBanner")
                .resizable()
                .scaledToFill()
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.86)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Image("ARVIOFeatureGraphic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260)
                Text("ARVIO")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
            }
            .padding(28)
        }
    }
}

struct HeroSection: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("ARVIOTVBanner")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            LinearGradient(colors: [Color.black.opacity(0.04), Color.black.opacity(0.35), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            LinearGradient(colors: [Color.black.opacity(0.78), Color.black.opacity(0.0)], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: 680, alignment: .leading)

                Text(heroMetadata)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)

                Text(item.overview?.nilIfBlank ?? item.episodeTitle?.nilIfBlank ?? item.subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: 660, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        Task { await playHero() }
                    } label: {
                        PrimaryButton(title: item.positionSeconds.map { $0 > 30 ? "Resume" : "Play" } ?? "Play")
                    }
                    .buttonStyle(.plain)
                    Button {
                        appState.selectedMedia = item
                    } label: {
                        SecondaryButton(title: "Details")
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await toggleWatchlist() }
                    } label: {
                        SecondaryButton(title: isSaved ? "In Watchlist" : "Watchlist")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
    }

    private var heroMetadata: String {
        [
            item.kind == .movie ? "Movie" : "Series",
            item.seasonEpisodeLabel,
            item.year.nilIfBlank,
            item.duration.nilIfBlank,
            item.rating.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private func playHero() async {
        appState.selectedMedia = item
        await appState.streams.resolve(item: item, season: item.season ?? 1, episode: item.episode ?? 1)
        guard appState.settings.profileSettings.autoPlaySingleSource,
              let stream = appState.streams.streams.first(where: \.isPlayable) else {
            return
        }
        appState.selectedStream = stream
    }

    private func toggleWatchlist() async {
        if isSaved {
            await appState.watchlist.remove(item)
            await appState.trakt.removeFromWatchlist(item: item)
        } else {
            await appState.watchlist.add(item)
            await appState.trakt.addToWatchlist(item: item)
        }
    }

    private var isSaved: Bool {
        appState.watchlist.contains(item) || appState.trakt.isInWatchlist(item)
    }
}

struct MediaRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let items: [MediaItem]
    var catalog: CatalogConfig? = nil
    var onRemove: ((MediaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
                if let catalog {
                    Button("View All") {
                        appState.selectedCatalog = catalog
                    }
                    .buttonStyle(.bordered)
                    .tint(ArvioTheme.gold)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if items.isEmpty {
                        EmptyStatePanel(title: "Nothing here yet", message: "Content will appear here after sync finishes.")
                    }
                    ForEach(items) { item in
                        ZStack(alignment: .topTrailing) {
                            MediaCard(item: item, layout: layout) { selected in
                                appState.selectedMedia = selected
                            }
                            if let onRemove {
                                Button {
                                    onRemove(item)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(ArvioTheme.textPrimary)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color.black.opacity(0.72)))
                                        .overlay(Circle().stroke(ArvioTheme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(7)
                                .accessibilityLabel("Remove from Continue Watching")
                            }
                        }
                    }
                }
            }
        }
    }

    private var layout: String {
        guard let catalog else { return appState.settings.profileSettings.cardLayoutMode }
        return appState.settings.profileSettings.catalogueRowLayoutModes[catalog.id]
            ?? (catalog.collectionTileShape == .poster ? "Portrait" : appState.settings.profileSettings.cardLayoutMode)
    }
}

struct LiveChannelRail: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let channels: [IptvChannel]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(channels.prefix(24)) { channel in
                        Button {
                            play(channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AsyncImage(url: channel.logo.flatMap(URL.init(string:))) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Image("ARVIOAppIcon").resizable().scaledToFit().opacity(0.8)
                                    }
                                }
                                .frame(width: 54, height: 54)
                                Text(channel.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(2)
                                Text(channel.group)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                    .lineLimit(1)
                                Spacer()
                                Text(appState.iptv.nowNextByChannelId[channel.id]?.now?.title ?? "LIVE")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(ArvioTheme.gold)
                                    .lineLimit(1)
                            }
                            .padding(14)
                            .frame(width: 210, height: 150, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func play(_ channel: IptvChannel) {
        appState.iptv.markOpened(channel)
        appState.selectedStream = channel.resolvedLiveStream(
            customUserAgent: appState.settings.profileSettings.customUserAgent
        )
    }
}

extension IptvChannel {
    var supportsCatchup: Bool {
        catchupDays > 0 ||
            catchupType?.nilIfBlank != nil ||
            catchupSource?.nilIfBlank != nil ||
            xtreamStreamId != nil ||
            streamUrl.range(of: "/timeshift/", options: .caseInsensitive) != nil ||
            streamUrl.range(of: "/live/", options: .caseInsensitive) != nil
    }

    func resolvedLiveStream(customUserAgent: String) -> ResolvedStream {
        let split = Self.splitUrlAndHeaders(streamUrl)
        let headers = Self.playbackHeaders(extra: split.headers, customUserAgent: customUserAgent)
        return ResolvedStream(
            addonId: nil,
            addonName: "Live TV",
            sourceName: group,
            title: name,
            quality: "Live",
            size: "",
            url: split.url.flatMap(URL.init(string:)),
            requestHeaders: headers,
            subtitles: [],
            isPlayable: split.url?.isEmpty == false,
            resumePositionSeconds: nil
        )
    }

    func resolvedCatchupStream(program: IptvProgram, customUserAgent: String) -> ResolvedStream {
        let rawUrl = catchupUrl(for: program) ?? streamUrl
        let split = Self.splitUrlAndHeaders(rawUrl)
        let headers = Self.playbackHeaders(extra: split.headers, customUserAgent: customUserAgent)
        return ResolvedStream(
            addonId: nil,
            addonName: "Live TV",
            sourceName: "\(group) Replay",
            title: "\(name) - \(program.title)",
            quality: "Catch-up",
            size: formatProgramWindow(program),
            url: split.url.flatMap(URL.init(string:)),
            requestHeaders: headers,
            subtitles: [],
            isPlayable: split.url?.isEmpty == false,
            resumePositionSeconds: nil
        )
    }

    func catchupUrl(for program: IptvProgram) -> String? {
        guard supportsCatchup, program.stop <= Date() else { return nil }
        return catchupUrlCandidates(for: program).first
    }

    private func catchupUrlCandidates(for program: IptvProgram) -> [String] {
        let startUnix = Int(program.start.timeIntervalSince1970)
        let endUnix = Int(program.stop.timeIntervalSince1970)
        let nowUnix = Int(Date().timeIntervalSince1970)
        let durationSeconds = max(1, Int(program.stop.timeIntervalSince(program.start)))
        let durationMinutes = max(1, (durationSeconds + 59) / 60)
        let streamId = xtreamStreamId ?? Self.xtreamStreamId(from: streamUrl)
        var candidates: [String] = []

        if let template = catchupSource?.nilIfBlank,
           let templated = Self.applyCatchupTemplate(
                template,
                channelUrl: streamUrl,
                program: program,
                startUnix: startUnix,
                endUnix: endUnix,
                nowUnix: nowUnix,
                durationSeconds: durationSeconds,
                durationMinutes: durationMinutes,
                streamId: streamId
           ) {
            candidates.append(templated)
        }

        if let xtream = Self.xtreamParts(from: streamUrl, explicitStreamId: streamId) {
            let startFormats = Self.catchupStartFormats(for: program.start)
            for start in startFormats {
                candidates.append("\(xtream.baseUrl)/timeshift/\(Self.pathEncode(xtream.username))/\(Self.pathEncode(xtream.password))/\(durationMinutes)/\(Self.pathEncode(start))/\(xtream.streamId).ts")
                candidates.append("\(xtream.baseUrl)/timeshift/\(Self.pathEncode(xtream.username))/\(Self.pathEncode(xtream.password))/\(durationMinutes)/\(Self.pathEncode(start))/\(xtream.streamId).m3u8")
                candidates.append("\(xtream.baseUrl)/streaming/timeshift.php?username=\(Self.queryEncode(xtream.username))&password=\(Self.queryEncode(xtream.password))&stream=\(xtream.streamId)&start=\(Self.queryEncode(start))&duration=\(durationMinutes)")
                candidates.append("\(xtream.baseUrl)/timeshift.php?username=\(Self.queryEncode(xtream.username))&password=\(Self.queryEncode(xtream.password))&stream_id=\(xtream.streamId)&start=\(Self.queryEncode(start))&duration=\(durationMinutes)")
            }
        }

        let resolvedType = catchupType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if resolvedType == "flussonic" || resolvedType == "ts" {
            candidates.append("\(streamUrl)\(streamUrl.contains("?") ? "&" : "?")utc=\(startUnix)")
        } else if resolvedType == "append" || resolvedType == "shift" {
            candidates.append("\(streamUrl)\(streamUrl.contains("?") ? "&" : "?")utc=\(startUnix)&lutc=\(nowUnix)")
        }

        var seen = Set<String>()
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func splitUrlAndHeaders(_ rawUrl: String) -> (url: String?, headers: [String: String]) {
        guard let separator = rawUrl.firstIndex(of: "|") else {
            return (rawUrl.trimmingCharacters(in: .whitespacesAndNewlines), [:])
        }
        let baseUrl = String(rawUrl[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHeaders = String(rawUrl[rawUrl.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var headers: [String: String] = [:]
        rawHeaders.split(separator: "&").forEach { entry in
            let entryString = String(entry)
            guard let equals = entryString.firstIndex(of: "=") else { return }
            let rawKey = String(entryString[..<equals])
            let rawValue = String(entryString[entryString.index(after: equals)...])
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            if isSafeHeader(key: key, value: value) {
                headers[key] = value
            }
        }
        return (baseUrl, headers)
    }

    private static func playbackHeaders(extra: [String: String], customUserAgent: String) -> [String: String] {
        let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        var headers: [String: String] = [
            "User-Agent": customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? defaultUserAgent,
            "Accept": "*/*",
            "Accept-Encoding": "identity"
        ]
        for (key, value) in extra where isSafeHeader(key: key, value: value) {
            headers[key] = value
        }
        if headers.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }),
           !headers.keys.contains(where: { $0.caseInsensitiveCompare("Origin") == .orderedSame }),
           let referer = headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value,
           let origin = origin(from: referer) {
            headers["Origin"] = origin
        }
        return headers
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

    private static func origin(from referer: String) -> String? {
        guard let url = URL(string: referer), let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            return isDefault ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func xtreamParts(
        from rawUrl: String,
        explicitStreamId: Int?
    ) -> (baseUrl: String, username: String, password: String, streamId: Int)? {
        let split = splitUrlAndHeaders(rawUrl)
        guard let urlString = split.url,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let liveIndex = parts.firstIndex(where: { $0.caseInsensitiveCompare("live") == .orderedSame }),
              parts.count > liveIndex + 3 else { return nil }
        let username = parts[liveIndex + 1].removingPercentEncoding ?? parts[liveIndex + 1]
        let password = parts[liveIndex + 2].removingPercentEncoding ?? parts[liveIndex + 2]
        let streamPart = parts[liveIndex + 3].split(separator: ".").first.map(String.init) ?? parts[liveIndex + 3]
        guard let streamId = explicitStreamId ?? Int(streamPart) else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return ("\(scheme)://\(host)\(port)", username, password, streamId)
    }

    private static func xtreamStreamId(from rawUrl: String) -> Int? {
        let split = splitUrlAndHeaders(rawUrl)
        guard let urlString = split.url,
              let url = URL(string: urlString) else { return nil }
        return url.path.split(separator: "/").last.flatMap { Int($0.split(separator: ".").first ?? "") }
    }

    private static func catchupStartFormats(for date: Date) -> [String] {
        [
            utcString(date, format: "yyyy-MM-dd:HH-mm"),
            utcString(date, format: "yyyy-MM-dd:HH-mm-ss"),
            utcString(date, format: "yyyy-MM-dd HH:mm"),
            utcString(date, format: "yyyy-MM-dd HH:mm:ss")
        ]
    }

    private static func applyCatchupTemplate(
        _ template: String,
        channelUrl: String,
        program: IptvProgram,
        startUnix: Int,
        endUnix: Int,
        nowUnix: Int,
        durationSeconds: Int,
        durationMinutes: Int,
        streamId: Int?
    ) -> String? {
        var value = template
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")

        let replacements: [String: String] = [
            "{utc}": "\(startUnix)", "${start}": "\(startUnix)", "{start}": "\(startUnix)", "$start": "\(startUnix)",
            "{timestamp}": "\(nowUnix)", "${timestamp}": "\(nowUnix)", "$timestamp": "\(nowUnix)",
            "{lutc}": "\(nowUnix)", "${lutc}": "\(nowUnix)", "$lutc": "\(nowUnix)",
            "${end}": "\(endUnix)", "{end}": "\(endUnix)", "$end": "\(endUnix)",
            "{duration}": "\(durationMinutes)", "${duration}": "\(durationMinutes)", "$duration": "\(durationMinutes)",
            "{duration_sec}": "\(durationSeconds)", "${duration_sec}": "\(durationSeconds)",
            "{channel}": streamId.map(String.init) ?? "", "${channel}": streamId.map(String.init) ?? "", "$channel": streamId.map(String.init) ?? "",
            "{channel_id}": streamId.map(String.init) ?? "", "${channel_id}": streamId.map(String.init) ?? "", "$channel_id": streamId.map(String.init) ?? "",
            "{stream}": streamId.map(String.init) ?? "", "${stream}": streamId.map(String.init) ?? "", "$stream": streamId.map(String.init) ?? "",
            "{stream_id}": streamId.map(String.init) ?? "", "${stream_id}": streamId.map(String.init) ?? "", "$stream_id": streamId.map(String.init) ?? ""
        ]
        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: token, with: replacement)
        }

        let startTokens = dateTokenValues(prefix: "start", date: program.start)
            .merging(dateTokenValues(prefix: nil, date: program.start)) { first, _ in first }
        let endTokens = dateTokenValues(prefix: "end", date: program.stop)
        for (token, replacement) in startTokens.merging(endTokens) { first, _ in first } {
            value = value.replacingOccurrences(of: token, with: replacement)
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        let split = splitUrlAndHeaders(channelUrl)
        guard let base = split.url, let url = URL(string: base), let scheme = url.scheme, let host = url.host else {
            return value.nilIfBlank
        }
        if value.hasPrefix("/") {
            let port = url.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)\(value)"
        }
        if value.hasPrefix("?") {
            return base.components(separatedBy: "?").first.map { "\($0)\(value)" }
        }
        if value.hasPrefix("&") {
            return "\(base)\(value)"
        }
        return value.nilIfBlank
    }

    private static func dateTokenValues(prefix: String?, date: Date) -> [String: String] {
        let values = [
            "Y": utcString(date, format: "yyyy"),
            "m": utcString(date, format: "MM"),
            "d": utcString(date, format: "dd"),
            "H": utcString(date, format: "HH"),
            "M": utcString(date, format: "mm"),
            "S": utcString(date, format: "ss")
        ]
        var tokens: [String: String] = [:]
        for (key, value) in values {
            if let prefix {
                tokens["{\(prefix):\(key)}"] = value
            } else {
                tokens["{\(key)}"] = value
            }
        }
        return tokens
    }

    private static func utcString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func pathEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func formatProgramWindow(_ program: IptvProgram) -> String {
        "\(Self.utcString(program.start, format: "HH:mm"))-\(Self.utcString(program.stop, format: "HH:mm"))"
    }
}

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let subtitle: String
    let items: [MediaItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(ArvioTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    if items.isEmpty {
                        EmptyStatePanel(title: "Nothing here yet", message: "Refresh or check your cloud connection.")
                    }
                    ForEach(items) { item in
                        MediaCard(item: item) { selected in
                            appState.selectedMedia = selected
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
    }
}

struct CatalogDetailView: View {
    @EnvironmentObject private var appState: AppState
    let config: CatalogConfig
    @State private var items: [MediaItem] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button("Back") { appState.selectedCatalog = nil }
                    .buttonStyle(.bordered)
                Text(config.title)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                if let description = config.collectionDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 17))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
                if isLoading {
                    ProgressView()
                        .tint(ArvioTheme.gold)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        MediaCard(item: item) { selected in
                            appState.selectedMedia = selected
                        }
                    }
                }
            }
            .padding(28)
        }
        .task(id: config.id) {
            isLoading = true
            items = await appState.catalogs.items(for: config)
            isLoading = false
        }
    }
}

private extension MediaItem {
    var seasonEpisodeLabel: String? {
        guard kind == .series else { return nil }
        if let season, let episode {
            return "S\(season) E\(episode)"
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
