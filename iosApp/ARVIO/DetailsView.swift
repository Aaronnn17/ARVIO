import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    @State private var details: TmdbDetails?
    @State private var recommendations: [MediaItem] = []
    @State private var collectionItems: [MediaItem] = []
    @State private var collectionTitle = ""
    @State private var reviews: [TmdbReview] = []
    @State private var episodes: [TmdbEpisode] = []
    @State private var cast: [TmdbCastMember] = []
    @State private var trailerURL: URL?
    @State private var showTrailerPlayer = false
    @State private var selectedPerson: TmdbPersonDetails?
    @State private var isLoadingPerson = false
    @State private var personError = ""
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1
    @State private var showSources = false
    @State private var actionStatus = ""

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    PosterBackdrop(item: item)
                        .frame(height: 440)
                    LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.42), Color.black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Button("Back") { appState.selectedMedia = nil }
                            .buttonStyle(.bordered)
                        Text(details?.title ?? details?.name ?? item.title)
                            .font(.system(size: 46, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(metadata)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ArvioTheme.textSecondary)
                        Text(details?.overview ?? item.overview ?? "")
                            .font(.system(size: 16))
                            .foregroundStyle(ArvioTheme.textSecondary)
                            .lineLimit(3)
                            .frame(maxWidth: 760, alignment: .leading)
                        HStack(spacing: 12) {
                            Button(playButtonTitle) {
                                Task { await playSelected() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ArvioTheme.gold)

                            Button("Sources") {
                                Task { await openSources() }
                            }
                            .buttonStyle(.bordered)

                            Button(appState.watchHistory.isWatched(currentPlaybackItem) ? "Watched" : "Mark Watched") {
                                Task {
                                    let wasWatched = appState.watchHistory.isWatched(currentPlaybackItem)
                                    await appState.watchHistory.toggleWatched(currentPlaybackItem)
                                    if !wasWatched {
                                        await appState.trakt.markWatched(item: currentPlaybackItem)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            Button(isSaved ? "In Watchlist" : "Watchlist") {
                                Task { await toggleWatchlist() }
                            }
                            .buttonStyle(.bordered)

                            if trailerURL != nil {
                                Button("Trailer") {
                                    showTrailerPlayer = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if !actionStatus.isEmpty {
                            Text(actionStatus)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ArvioTheme.textSecondary)
                        }
                    }
                    .padding(28)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if item.kind == .series, let seasons = details?.seasons?.filter({ $0.seasonNumber > 0 }) {
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(seasons) { season in
                            Text(season.name ?? "Season \(season.seasonNumber)").tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSeason) { _, value in
                        selectedEpisode = 1
                        Task { await loadEpisodes(season: value) }
                    }

                    episodeGrid
                }

                if showSources || appState.streams.isLoading || !appState.streams.streams.isEmpty || appState.streams.errorMessage != nil {
                    SourceSelector()
                }

                if !cast.isEmpty {
                    castRail
                }

                if !collectionItems.isEmpty {
                    MediaRail(title: collectionTitle.isEmpty ? "Collection" : collectionTitle, items: collectionItems)
                }

                if !reviews.isEmpty {
                    reviewsRail
                }

                if !recommendations.isEmpty {
                    MediaRail(title: "More Like This", items: recommendations)
                }
            }
                .padding(28)
            }
            if showTrailerPlayer, let trailerURL {
                TrailerPlayerView(url: trailerURL, soundEnabled: appState.settings.profileSettings.trailerSoundEnabled) {
                    showTrailerPlayer = false
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if isLoadingPerson || selectedPerson != nil || !personError.isEmpty {
                PersonModalView(
                    person: selectedPerson,
                    isLoading: isLoadingPerson,
                    errorMessage: personError,
                    onClose: closePersonModal,
                    onMediaSelect: { media in
                        closePersonModal()
                        appState.selectedMedia = media
                    }
                )
                .transition(.opacity)
                .zIndex(11)
            }
        }
        .task(id: item.id) {
            details = nil
            recommendations = []
            collectionItems = []
            collectionTitle = ""
            reviews = []
            episodes = []
            cast = []
            trailerURL = nil
            selectedPerson = nil
            personError = ""
            isLoadingPerson = false
            selectedSeason = item.season ?? 1
            selectedEpisode = item.episode ?? 1
            showSources = false
            actionStatus = ""
            async let loadedDetails = try? appState.tmdb.details(for: item)
            async let loadedRecommendations = try? appState.tmdb.recommendations(for: item)
            async let loadedReviews = try? appState.tmdb.reviews(for: item)
            async let loadedCast = try? appState.tmdb.cast(for: item)
            async let loadedTrailer = try? appState.tmdb.trailerURL(for: item)
            let detailResult = await loadedDetails
            details = detailResult ?? details
            recommendations = await loadedRecommendations ?? []
            reviews = await loadedReviews ?? []
            cast = await loadedCast ?? []
            trailerURL = await loadedTrailer ?? trailerURL
            if let collection = detailResult?.belongsToCollection {
                collectionTitle = collection.name ?? "Collection"
                collectionItems = (try? await appState.tmdb.collectionItems(collectionId: collection.id, limit: 24)) ?? []
            }
            if appState.settings.profileSettings.trailerAutoPlay, trailerURL != nil {
                showTrailerPlayer = true
            }
            if item.kind == .series {
                await loadEpisodes(season: selectedSeason)
            }
        }
    }

    private var episodeGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Episodes")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(episodes) { episode in
                    Button {
                        selectedEpisode = episode.episodeNumber
                        Task { await playSelected() }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("E\(episode.episodeNumber)")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(episode.episodeNumber == selectedEpisode ? ArvioTheme.gold : ArvioTheme.textSecondary))
                                Spacer()
                                if appState.watchHistory.isWatched(episodePlaybackItem(episode)) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green.opacity(0.95))
                                }
                                if let runtime = episode.runtime, runtime > 0 {
                                    Text("\(runtime)m")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ArvioTheme.textTertiary)
                                }
                            }
                            Text(episode.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                                .lineLimit(2)
                            Text(episode.overview ?? episode.airDate ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(ArvioTheme.textSecondary)
                                .lineLimit(3)
                        }
                        .padding(14)
                        .frame(minHeight: 132, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(episode.episodeNumber == selectedEpisode ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var castRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cast) { person in
                        Button {
                            Task { await openPerson(person.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: person.imageURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.white.opacity(0.08)
                                    }
                                }
                                .frame(width: 116, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(person.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                    .lineLimit(1)
                                Text(person.character ?? "")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(width: 116, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var reviewsRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reviews")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(reviews) { review in
                        ReviewCard(review: review)
                    }
                }
            }
        }
    }

    private var currentPlaybackItem: MediaItem {
        guard item.kind == .series else { return item }
        return MediaItem(
            id: "\(item.id)-s\(selectedSeason)e\(selectedEpisode)",
            tmdbId: item.tmdbId,
            title: item.title,
            subtitle: item.subtitle,
            year: item.year,
            duration: item.duration,
            rating: item.rating,
            kind: item.kind,
            progress: item.progress,
            palette: item.palette,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            overview: item.overview,
            season: selectedSeason,
            episode: selectedEpisode,
            episodeTitle: episodes.first(where: { $0.episodeNumber == selectedEpisode })?.name,
            positionSeconds: item.positionSeconds,
            durationSeconds: item.durationSeconds
        )
    }

    private func episodePlaybackItem(_ episode: TmdbEpisode) -> MediaItem {
        MediaItem(
            id: "\(item.id)-s\(selectedSeason)e\(episode.episodeNumber)",
            tmdbId: item.tmdbId,
            title: item.title,
            subtitle: item.subtitle,
            year: item.year,
            duration: episode.runtime.map { "\($0)m" } ?? item.duration,
            rating: item.rating,
            kind: item.kind,
            progress: 0,
            palette: item.palette,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            overview: item.overview,
            season: selectedSeason,
            episode: episode.episodeNumber,
            episodeTitle: episode.name,
            positionSeconds: nil,
            durationSeconds: episode.runtime.map { $0 * 60 }
        )
    }

    private func loadEpisodes(season: Int) async {
        episodes = (try? await appState.tmdb.seasonEpisodes(for: item, season: season)) ?? []
    }

    private func resolveSelectedSource(autoPlay: Bool) async {
        appState.selectedMedia = currentPlaybackItem
        showSources = !autoPlay || !appState.settings.profileSettings.autoPlaySingleSource
        actionStatus = autoPlay && appState.settings.profileSettings.autoPlaySingleSource ? "Loading best source..." : "Loading sources..."
        await appState.streams.resolve(item: currentPlaybackItem, season: selectedSeason, episode: selectedEpisode)
        let playable = appState.streams.streams.filter {
            $0.isPlayable && meetsMinimumQuality($0.quality, minimum: appState.settings.profileSettings.autoPlayMinQuality)
        }
        if autoPlay && appState.settings.profileSettings.autoPlaySingleSource {
            if let best = playable.first ?? appState.streams.streams.first(where: \.isPlayable) {
                actionStatus = ""
                appState.selectedStream = best
            } else {
                showSources = true
                actionStatus = "No playable source found. Pick another source or check addon configuration."
            }
        } else if playable.isEmpty {
            actionStatus = "No playable source found."
        } else {
            actionStatus = "\(playable.count) playable source\(playable.count == 1 ? "" : "s") ready."
        }
    }

    private func playSelected() async {
        await resolveSelectedSource(autoPlay: true)
    }

    private func openSources() async {
        await resolveSelectedSource(autoPlay: false)
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

    private func openPerson(_ personId: Int) async {
        isLoadingPerson = true
        selectedPerson = nil
        personError = ""
        do {
            selectedPerson = try await appState.tmdb.personDetails(personId: personId)
        } catch {
            personError = error.localizedDescription
        }
        isLoadingPerson = false
    }

    private func closePersonModal() {
        selectedPerson = nil
        personError = ""
        isLoadingPerson = false
    }

    private var isSaved: Bool {
        appState.watchlist.contains(item) || appState.trakt.isInWatchlist(item)
    }

    private var playButtonTitle: String {
        if let position = currentPlaybackItem.positionSeconds, position > 30 {
            return "Resume"
        }
        return "Play"
    }

    private var metadata: String {
        let year = details?.releaseDate?.prefix(4) ?? details?.firstAirDate?.prefix(4) ?? Substring(item.year)
        let rating = details?.voteAverage.map { String(format: "%.1f", $0) } ?? item.rating
        let genres = details?.genres?.prefix(3).map(\.name).joined(separator: ", ") ?? item.subtitle
        let runtime = details?.runtime.map { "\($0)m" } ??
            details?.episodeRunTime?.first.map { "\($0)m" } ??
            item.duration
        return [String(year), rating.isEmpty ? nil : "TMDB \(rating)", runtime.isEmpty ? nil : runtime, genres].compactMap { $0 }.joined(separator: " - ")
    }

    private func meetsMinimumQuality(_ quality: String, minimum: String) -> Bool {
        qualityRank(quality) >= qualityRank(minimum)
    }

    private func qualityRank(_ value: String) -> Int {
        if value == "Any" || value == "Unknown" { return 0 }
        return SharedCoreBridge.qualityRank(value)
    }
}

struct SourceSelector: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedGroup = "All Sources"

    var body: some View {
        let streams = sortedStreams
        let groups = sourceGroups(for: streams)
        let tabs = ["All Sources"] + groups
        let activeGroup = tabs.contains(selectedGroup) ? selectedGroup : "All Sources"
        let visibleStreams = filteredStreams(streams, group: activeGroup)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sources")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Spacer()
                if appState.streams.isLoading {
                    ProgressView()
                }
            }

            sourceStats(streams)

            if tabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.self) { tab in
                            Button {
                                selectedGroup = tab
                            } label: {
                                Text(tab)
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(tab == activeGroup ? Color.black : ArvioTheme.textSecondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(tab == activeGroup ? ArvioTheme.gold : Color.white.opacity(0.06)))
                                    .overlay(Capsule().stroke(tab == activeGroup ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let error = appState.streams.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if streams.isEmpty && !appState.streams.isLoading {
                EmptyStatePanel(
                    title: "No sources loaded",
                    message: appState.addons.addons.isEmpty ? "Install stream addons first." : "Press Play to resolve addon sources."
                )
            } else {
                LazyVStack(spacing: 10) {
                    if appState.plugins.groupStreamsByRepository {
                        ForEach(sourceSections(for: visibleStreams)) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(ArvioTheme.gold)
                                    Text("\(section.streams.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(ArvioTheme.textTertiary)
                                    Spacer()
                                }
                                ForEach(section.streams) { stream in
                                    sourceRow(stream, isTopResult: stream.id == streams.first?.id)
                                }
                            }
                        }
                    } else {
                        ForEach(visibleStreams) { stream in
                            sourceRow(stream, isTopResult: stream.id == streams.first?.id)
                        }
                    }
                }
            }
        }
    }

    private var sortedStreams: [ResolvedStream] {
        appState.streams.streams.sorted {
            sourceScore($0) > sourceScore($1)
        }
    }

    private func sourceGroups(for streams: [ResolvedStream]) -> [String] {
        var seen = Set<String>()
        return streams.compactMap { stream in
            let key = groupTitle(for: stream)
            return seen.insert(key).inserted ? key : nil
        }
    }

    private func filteredStreams(_ streams: [ResolvedStream], group: String) -> [ResolvedStream] {
        guard group != "All Sources" else { return streams }
        return streams.filter { groupTitle(for: $0) == group }
    }

    private func sourceSections(for streams: [ResolvedStream]) -> [SourceSection] {
        var order: [String] = []
        var grouped: [String: [ResolvedStream]] = [:]
        for stream in streams {
            let title = groupTitle(for: stream)
            if grouped[title] == nil { order.append(title) }
            grouped[title, default: []].append(stream)
        }
        return order.map { SourceSection(title: $0, streams: grouped[$0] ?? []) }
    }

    private func groupTitle(for stream: ResolvedStream) -> String {
        stream.addonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? stream.sourceName
            : stream.addonName
    }

    private func sourceStats(_ streams: [ResolvedStream]) -> some View {
        HStack(spacing: 8) {
            statPill("Total", "\(streams.count)", Color.blue.opacity(0.9))
            statPill("Playable", "\(streams.filter(\.isPlayable).count)", Color.green.opacity(0.9))
            statPill("4K", "\(streams.filter { sourceText($0).localizedCaseInsensitiveContains("4K") || sourceText($0).contains("2160") }.count)", ArvioTheme.gold)
            statPill("1080p", "\(streams.filter { sourceText($0).contains("1080") }.count)", Color.purple.opacity(0.9))
            statPill("Subs", "\(streams.filter { !$0.subtitles.isEmpty }.count)", Color.cyan.opacity(0.9))
        }
    }

    private func statPill(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(value)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ArvioTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.055)))
        .overlay(Capsule().stroke(ArvioTheme.border, lineWidth: 1))
    }

    private func sourceRow(_ stream: ResolvedStream, isTopResult: Bool) -> some View {
        Button {
            if stream.isPlayable {
                appState.selectedStream = stream
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(stream.sourceName.isEmpty ? stream.addonName : stream.sourceName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                            .lineLimit(1)
                        if isTopResult {
                            sourceBadge("Best", color: ArvioTheme.gold, filled: true)
                        }
                        if isCachedLike(stream) {
                            sourceBadge("Cached", color: Color.green.opacity(0.92), filled: false)
                        }
                    }

                    Text(stream.title.isEmpty ? stream.addonName : stream.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .lineLimit(2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            sourceBadge(stream.quality.isEmpty ? "Direct" : stream.quality, color: ArvioTheme.gold, filled: false)
                            if !stream.size.isEmpty {
                                sourceBadge(stream.size, color: Color.blue.opacity(0.88), filled: false)
                            }
                            sourceBadge(stream.isPlayable ? "Playable" : "Needs resolver", color: stream.isPlayable ? Color.green.opacity(0.9) : Color.orange.opacity(0.9), filled: false)
                            if !stream.subtitles.isEmpty {
                                sourceBadge("\(stream.subtitles.count) subs", color: Color.cyan.opacity(0.9), filled: false)
                            }
                            sourceBadge(stream.addonName.isEmpty ? "Unknown addon" : stream.addonName, color: Color.white.opacity(0.65), filled: false)
                        }
                    }
                }
                Spacer()
                Image(systemName: stream.isPlayable ? "play.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(stream.isPlayable ? ArvioTheme.gold : Color.orange.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(isTopResult ? ArvioTheme.gold.opacity(0.11) : ArvioTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(stream.isPlayable ? ArvioTheme.gold.opacity(isTopResult ? 0.9 : 0.55) : ArvioTheme.border, lineWidth: 1))
            .opacity(stream.isPlayable ? 1 : 0.68)
        }
        .buttonStyle(.plain)
        .disabled(!stream.isPlayable)
    }

    private func sourceBadge(_ label: String, color: Color, filled: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(filled ? Color.black : color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(filled ? color : color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.7), lineWidth: 1))
    }

    private func sourceScore(_ stream: ResolvedStream) -> Int {
        SharedCoreBridge.streamScore(
            quality: stream.quality,
            size: stream.size,
            addonName: stream.addonName,
            sourceName: stream.sourceName,
            title: stream.title,
            isPlayable: stream.isPlayable,
            preferredLanguage: appState.settings.profileSettings.defaultAudioLanguage,
            cached: isCachedLike(stream)
        )
    }

    private func isCachedLike(_ stream: ResolvedStream) -> Bool {
        let text = sourceText(stream).lowercased()
        return text.contains("cached") ||
            text.contains("rd+") ||
            text.contains("real-debrid") ||
            text.contains("premiumize") ||
            text.contains("torbox")
    }

    private func sourceText(_ stream: ResolvedStream) -> String {
        [stream.addonName, stream.sourceName, stream.title, stream.quality, stream.size]
            .joined(separator: " ")
    }
}

private struct SourceSection: Identifiable {
    let title: String
    let streams: [ResolvedStream]

    var id: String { title }
}

private struct ReviewCard: View {
    let review: TmdbReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AsyncImage(url: review.authorDetails?.avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.08))
                            Text(String(review.displayAuthor.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(ArvioTheme.textTertiary)
                        }
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(review.displayAuthor)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .lineLimit(1)
                    if let rating = review.ratingText {
                        Text("TMDB \(rating)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(ArvioTheme.gold)
                    }
                }
                Spacer()
            }

            Text(review.content)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ArvioTheme.textSecondary)
                .lineSpacing(3)
                .lineLimit(6)
        }
        .padding(14)
        .frame(width: 330, height: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}

private struct PersonModalView: View {
    let person: TmdbPersonDetails?
    let isLoading: Bool
    let errorMessage: String
    let onClose: () -> Void
    let onMediaSelect: (MediaItem) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            LinearGradient(
                colors: [ArvioTheme.gold.opacity(0.1), Color.clear, Color.black.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(ArvioTheme.gold)
            } else if let person {
                personContent(person)
            } else {
                VStack(spacing: 16) {
                    Text("Cast details unavailable")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                    Button("Close", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                }
            }
        }
    }

    private func personContent(_ person: TmdbPersonDetails) -> some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .center, spacing: 18) {
                AsyncImage(url: person.imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.08)
                            Text(String(person.name.prefix(1)))
                                .font(.system(size: 54, weight: .black))
                                .foregroundStyle(ArvioTheme.textTertiary)
                        }
                    }
                }
                .frame(width: 210, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

                VStack(spacing: 8) {
                    if let birthday = person.birthday, !birthday.isEmpty {
                        personFact(title: "Born", value: formatDate(birthday))
                    }
                    if let place = person.placeOfBirth, !place.isEmpty {
                        personFact(title: "From", value: place)
                    }
                }
            }
            .frame(width: 230)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(person.name)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                            .lineLimit(2)
                        Text("Cast & credits")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(ArvioTheme.gold)
                    }
                    Spacer()
                    Button("Close", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                        .keyboardShortcut(.escape, modifiers: [])
                }

                Text(personBiography(person))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(8)
                    .frame(maxWidth: 760, alignment: .leading)

                if !person.knownFor.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Known For")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(person.knownFor) { item in
                                    MediaCard(item: item, layout: "Portrait") { selected in
                                        onMediaSelect(selected)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(34)
    }

    private func personFact(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(ArvioTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ArvioTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private func personBiography(_ person: TmdbPersonDetails) -> String {
        let value = person.biography?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "No biography available." : value
    }

    private func formatDate(_ raw: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: raw) else { return raw }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }
}
