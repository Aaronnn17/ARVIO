import AVKit
import Combine
import SwiftUI

private struct PlayerTrackOption: Identifiable {
    let id: String
    let title: String
    let option: AVMediaSelectionOption?
}

private struct ExternalSubtitleCue: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
}

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let stream: ResolvedStream
    @State private var player: AVPlayer?
    @State private var didSeek = false
    @State private var didSaveProgress = false
    @State private var isPlaying = true
    @State private var showControls = true
    @State private var showSources = false
    @State private var showTracks = false
    @State private var audioOptions: [PlayerTrackOption] = []
    @State private var subtitleOptions: [PlayerTrackOption] = [PlayerTrackOption(id: "off", title: "Off", option: nil)]
    @State private var selectedAudioId = ""
    @State private var selectedSubtitleId = "off"
    @State private var externalSubtitleCues: [ExternalSubtitleCue] = []
    @State private var selectedExternalSubtitleId = "off"
    @State private var currentCaption = ""
    @State private var isTranslatingSubtitles = false
    @State private var subtitleStatus = ""
    @State private var playbackErrorMessage = ""
    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var lastProgressSaveSeconds = 0.0
    @State private var isSavingProgress = false
    @State private var didMarkWatched = false
    @State private var skipIntervals: [SkipInterval] = []
    @State private var dismissedSkipIntervalIds: Set<String> = []
    private let progressTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if !currentCaption.isEmpty {
                VStack {
                    Spacer()
                    Text(currentCaption)
                        .font(captionFont)
                        .foregroundStyle(captionColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(captionBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 8)
                        .padding(.horizontal, 60)
                        .padding(.bottom, captionBottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            if !playbackErrorMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(ArvioTheme.gold)
                    Text("Playback failed")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Text(playbackErrorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    if !appState.streams.streams.filter(\.isPlayable).isEmpty {
                        Button("Try Another Source") {
                            Task { await switchToNextPlayableSource() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                    }
                }
                .padding(24)
                .frame(width: 430)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.78)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            Color.black.opacity(showControls ? 0.24 : 0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showControls.toggle()
                    }
                }

            if let interval = activeSkipInterval {
                skipButton(interval)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if showControls {
                playerHUD
                    .transition(.opacity)
            }
        }
        .task(id: stream.id) {
            guard let url = stream.url else { return }
            didSeek = false
            didSaveProgress = false
            currentSeconds = 0
            durationSeconds = 0
            lastProgressSaveSeconds = 0
            isSavingProgress = false
            didMarkWatched = false
            externalSubtitleCues = []
            selectedExternalSubtitleId = "off"
            currentCaption = ""
            subtitleStatus = ""
            playbackErrorMessage = ""
            skipIntervals = []
            dismissedSkipIntervalIds = []
            let asset = stream.requestHeaders.isEmpty
                ? AVURLAsset(url: url)
                : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.requestHeaders])
            let created = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = created
            if let seconds = stream.resumePositionSeconds, seconds > 5, !didSeek {
                didSeek = true
                await created.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600))
            }
            created.play()
            isPlaying = true
            loadTrackOptions(from: created.currentItem)
            await autoSelectExternalSubtitleIfNeeded()
            await loadSkipIntervalsIfNeeded()
        }
        .onReceive(progressTimer) { _ in
            updateProgress()
            Task { await savePeriodicProgressIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item == player?.currentItem else { return }
            Task { await handlePlaybackEnded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item == player?.currentItem else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            playbackErrorMessage = error?.localizedDescription ?? item.error?.localizedDescription ?? "This source is not playable on iOS."
        }
        .onDisappear {
            Task { await saveProgressIfNeeded() }
            player?.pause()
            player = nil
        }
    }

    private var playerHUD: some View {
        VStack {
            HStack(alignment: .top, spacing: 14) {
                Button("Close") {
                    Task { await closePlayer() }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .keyboardShortcut(.escape, modifiers: [])

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.selectedMedia?.title ?? stream.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .lineLimit(1)
                    Text([stream.addonName, stream.sourceName, stream.quality, stream.size].filter { !$0.isEmpty }.joined(separator: " - "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(isPlaying ? "Pause" : "Play") { togglePlayback() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [])
                Button(showSources ? "Hide Sources" : "Sources") { showSources.toggle() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("s", modifiers: [])
                Button(showTracks ? "Hide Tracks" : "Tracks") { showTracks.toggle() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("t", modifiers: [])
            }
            .padding(24)

            Spacer()

            if showSources || showTracks {
                HStack(alignment: .bottom, spacing: 18) {
                    if showSources {
                        sourcePanel
                    }
                    if showTracks {
                        tracksPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }

            VStack(spacing: 8) {
                ProgressView(value: durationSeconds > 0 ? currentSeconds / durationSeconds : 0)
                    .tint(ArvioTheme.gold)
                HStack {
                    Text(timeLabel(currentSeconds))
                    Spacer()
                    Text(durationSeconds > 0 ? timeLabel(durationSeconds) : "--:--")
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(ArvioTheme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }

    private var activeSkipInterval: SkipInterval? {
        skipIntervals.first { interval in
            currentSeconds >= interval.startSeconds &&
                currentSeconds < interval.endSeconds &&
                !dismissedSkipIntervalIds.contains(interval.id)
        }
    }

    private func skipButton(_ interval: SkipInterval) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    skip(interval)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "forward.end.fill")
                        Text(interval.label)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(ArvioTheme.gold))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: ArvioTheme.gold.opacity(0.35), radius: 16)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.trailing, 42)
            .padding(.bottom, 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.streams.streams.filter(\.isPlayable)) { candidate in
                        Button {
                            Task { await switchSource(candidate) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.sourceName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ArvioTheme.textPrimary)
                                        .lineLimit(1)
                                    Text([candidate.addonName, candidate.quality, candidate.size].filter { !$0.isEmpty }.joined(separator: " - "))
                                        .font(.system(size: 12))
                                        .foregroundStyle(ArvioTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if candidate.id == stream.id {
                                    Text("Now")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(ArvioTheme.gold))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(candidate.id == stream.id ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 420)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private var tracksPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            trackSection(title: "Audio", options: audioOptions, selectedId: selectedAudioId) { id in
                selectTrack(id: id, characteristic: .audible)
            }
            trackSection(title: "Subtitles", options: subtitleOptions, selectedId: selectedSubtitleId) { id in
                selectTrack(id: id, characteristic: .legible)
            }
            externalSubtitleSection
        }
        .frame(width: 340)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private func trackSection(title: String, options: [PlayerTrackOption], selectedId: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            if options.isEmpty {
                Text("No embedded tracks")
                    .font(.system(size: 13))
                    .foregroundStyle(ArvioTheme.textTertiary)
            } else {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            if option.id == selectedId {
                                Text("Selected")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ArvioTheme.gold)
                            }
                        }
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(option.id == selectedId ? ArvioTheme.gold.opacity(0.14) : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if appState.settings.globalSettings.subtitleAiEnabled {
                Button(isTranslatingSubtitles ? "Translating..." : "AI Translate Loaded") {
                    Task { await translateLoadedSubtitles() }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .disabled(externalSubtitleCues.isEmpty || isTranslatingSubtitles || appState.settings.globalSettings.subtitleAiApiKey.isEmpty)
                if !subtitleStatus.isEmpty {
                    Text(subtitleStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(subtitleStatus.localizedCaseInsensitiveContains("failed") ? Color.red.opacity(0.9) : ArvioTheme.textTertiary)
                }
            }
        }
    }

    private var externalSubtitleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("External")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            let options = [ResolvedSubtitle(id: "off", label: "Off", language: "off", url: URL(string: "https://arvio.local/off")!)] + stream.subtitles
            if options.count == 1 {
                Text("No addon subtitles")
                    .font(.system(size: 13))
                    .foregroundStyle(ArvioTheme.textTertiary)
            } else {
                ForEach(options) { subtitle in
                    Button {
                        Task { await selectExternalSubtitle(subtitle) }
                    } label: {
                        HStack {
                            Text(subtitle.label)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if subtitle.id == selectedExternalSubtitleId {
                                Text("Selected")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ArvioTheme.gold)
                            }
                        }
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(subtitle.id == selectedExternalSubtitleId ? ArvioTheme.gold.opacity(0.14) : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func closePlayer() async {
        await saveProgressIfNeeded()
        appState.selectedStream = nil
    }

    private func switchSource(_ candidate: ResolvedStream) async {
        await saveProgressIfNeeded()
        appState.selectedStream = candidate
    }

    private func switchToNextPlayableSource() async {
        let playable = appState.streams.streams.filter(\.isPlayable)
        guard !playable.isEmpty else { return }
        let currentIndex = playable.firstIndex(where: { $0.id == stream.id }) ?? -1
        let next = playable.dropFirst(currentIndex + 1).first ?? playable.first
        guard let next, next.id != stream.id else { return }
        await switchSource(next)
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func skip(_ interval: SkipInterval) {
        guard let player else { return }
        dismissedSkipIntervalIds.insert(interval.id)
        let target = max(0, interval.endSeconds + 0.25)
        currentSeconds = target
        Task {
            await player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        if !isPlaying {
            player.play()
            isPlaying = true
        }
    }

    private func updateProgress() {
        guard let player else { return }
        if let item = player.currentItem, item.status == .failed {
            playbackErrorMessage = item.error?.localizedDescription ?? "This source is not playable on iOS."
            isPlaying = false
        }
        let current = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        if current.isFinite { currentSeconds = current }
        if duration.isFinite && duration > 0 { durationSeconds = duration }
        currentCaption = externalSubtitleCues.first { $0.start <= currentSeconds && $0.end >= currentSeconds }?.text ?? ""
    }

    private func loadSkipIntervalsIfNeeded() async {
        guard let media = appState.selectedMedia,
              media.kind == .series,
              let season = media.season,
              let episode = media.episode else {
            return
        }
        do {
            let externalIds = try await appState.tmdb.externalIds(for: media)
            skipIntervals = await SkipIntroService.shared.intervals(
                imdbId: externalIds.imdbId,
                season: season,
                episode: episode
            )
        } catch {
            skipIntervals = []
        }
    }

    private func loadTrackOptions(from item: AVPlayerItem?) {
        guard let item else {
            audioOptions = []
            subtitleOptions = [PlayerTrackOption(id: "off", title: "Off", option: nil)]
            return
        }
        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            audioOptions = group.options.enumerated().map { index, option in
                PlayerTrackOption(id: "audio-\(index)-\(option.displayName)", title: option.displayName, option: option)
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
               let selectedIndex = group.options.firstIndex(where: { $0 === selected }) {
                selectedAudioId = "audio-\(selectedIndex)-\(selected.displayName)"
            } else {
                selectedAudioId = audioOptions.first?.id ?? ""
            }
        } else {
            audioOptions = []
            selectedAudioId = ""
        }

        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            let options = group.options.enumerated().map { index, option in
                PlayerTrackOption(id: "subtitle-\(index)-\(option.displayName)", title: option.displayName, option: option)
            }
            subtitleOptions = [PlayerTrackOption(id: "off", title: "Off", option: nil)] + options
            if let preferred = preferredEmbeddedSubtitle(in: group) {
                item.select(preferred, in: group)
                if let selectedIndex = group.options.firstIndex(where: { $0 === preferred }) {
                    selectedSubtitleId = "subtitle-\(selectedIndex)-\(preferred.displayName)"
                }
            } else if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
               let selectedIndex = group.options.firstIndex(where: { $0 === selected }) {
                selectedSubtitleId = "subtitle-\(selectedIndex)-\(selected.displayName)"
            } else {
                selectedSubtitleId = "off"
            }
        } else {
            subtitleOptions = [PlayerTrackOption(id: "off", title: "Off", option: nil)]
            selectedSubtitleId = "off"
        }
    }

    private func selectTrack(id: String, characteristic: AVMediaCharacteristic) {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }
        let options = characteristic == .audible ? audioOptions : subtitleOptions
        guard let selected = options.first(where: { $0.id == id }) else { return }
        item.select(selected.option, in: group)
        if characteristic == .audible {
            selectedAudioId = id
        } else {
            selectedSubtitleId = id
            selectedExternalSubtitleId = "off"
            externalSubtitleCues = []
            currentCaption = ""
        }
    }

    private func selectExternalSubtitle(_ subtitle: ResolvedSubtitle) async {
        if subtitle.id == "off" {
            selectedExternalSubtitleId = "off"
            externalSubtitleCues = []
            currentCaption = ""
            subtitleStatus = ""
            return
        }
        selectedSubtitleId = "off"
        selectTrack(id: "off", characteristic: .legible)
        selectedExternalSubtitleId = subtitle.id
        do {
            let (data, _) = try await URLSession.shared.data(from: subtitle.url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                externalSubtitleCues = []
                return
            }
            externalSubtitleCues = Self.parseSubtitleCues(text)
            if appState.settings.globalSettings.subtitleRemoveHearingImpaired {
                externalSubtitleCues = externalSubtitleCues.compactMap { cue in
                    let cleaned = Self.cleanHearingImpairedText(cue.text)
                    return cleaned.isEmpty ? nil : ExternalSubtitleCue(start: cue.start, end: cue.end, text: cleaned)
                }
            }
            subtitleStatus = externalSubtitleCues.isEmpty ? "No cues found" : "\(externalSubtitleCues.count) cues loaded"
            if appState.settings.globalSettings.subtitleAiAutoSelect && appState.settings.globalSettings.subtitleAiEnabled {
                await translateLoadedSubtitles()
            }
        } catch {
            externalSubtitleCues = []
            currentCaption = ""
            subtitleStatus = "Subtitle load failed"
        }
    }

    private func translateLoadedSubtitles() async {
        guard !externalSubtitleCues.isEmpty, !isTranslatingSubtitles else { return }
        let target = aiTargetLanguage
        let apiKey = appState.settings.globalSettings.subtitleAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !apiKey.isEmpty else {
            subtitleStatus = "AI subtitle settings incomplete"
            return
        }
        isTranslatingSubtitles = true
        subtitleStatus = "Translating to \(target)..."
        defer { isTranslatingSubtitles = false }

        var translatedTexts: [String] = []
        let texts = externalSubtitleCues.map(\.text)
        let chunkSize = 40
        for start in stride(from: 0, to: texts.count, by: chunkSize) {
            let end = min(start + chunkSize, texts.count)
            let chunk = Array(texts[start..<end])
            let result = await SubtitleTranslationService.translateBatch(
                lines: chunk,
                targetLanguage: target,
                apiKey: apiKey,
                model: appState.settings.globalSettings.subtitleAiModel
            )
            guard result.success else {
                subtitleStatus = "AI translation failed: \(result.errorMessage ?? "unknown error")"
                return
            }
            translatedTexts.append(contentsOf: result.lines)
            subtitleStatus = "Translated \(translatedTexts.count)/\(texts.count)"
        }
        guard translatedTexts.count == externalSubtitleCues.count else {
            subtitleStatus = "AI translation failed: line mismatch"
            return
        }
        externalSubtitleCues = zip(externalSubtitleCues, translatedTexts).map { cue, text in
            ExternalSubtitleCue(start: cue.start, end: cue.end, text: text)
        }
        subtitleStatus = "AI subtitles active: \(target)"
    }

    private func handlePlaybackEnded() async {
        await saveProgressIfNeeded()
        guard appState.settings.profileSettings.autoPlayNext,
              let media = appState.selectedMedia,
              media.kind == .series,
              let season = media.season,
              let episode = media.episode else {
            return
        }
        let next = MediaItem(
            id: "\(media.id)-next-\(episode + 1)",
            tmdbId: media.tmdbId,
            title: media.title,
            subtitle: media.subtitle,
            year: media.year,
            duration: media.duration,
            rating: media.rating,
            kind: media.kind,
            progress: 0,
            palette: media.palette,
            posterPath: media.posterPath,
            backdropPath: media.backdropPath,
            overview: media.overview,
            season: season,
            episode: episode + 1
        )
        appState.selectedMedia = next
        await appState.streams.resolve(item: next, season: season, episode: episode + 1)
        if let nextStream = appState.streams.streams.first(where: { $0.isPlayable }) {
            appState.selectedStream = nextStream
        }
    }

    private func saveProgressIfNeeded() async {
        guard !didSaveProgress else { return }
        didSaveProgress = true
        await persistProgress(force: true)
    }

    private func savePeriodicProgressIfNeeded() async {
        guard currentSeconds - lastProgressSaveSeconds >= 20 else { return }
        await persistProgress(force: false)
    }

    private func persistProgress(force: Bool) async {
        guard !isSavingProgress, let media = appState.selectedMedia, let player else { return }
        let current = player.currentTime().seconds
        let rawDuration = player.currentItem?.duration.seconds ?? 0
        let fallbackDuration = Double(media.durationSeconds ?? 0)
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : fallbackDuration
        guard current.isFinite else { return }
        let positionSeconds = Int(current.rounded())
        let durationSeconds = Int(duration.rounded())
        guard SharedCoreBridge.shouldSaveProgress(positionSeconds: positionSeconds, durationSeconds: durationSeconds) else { return }
        guard force || abs(Double(positionSeconds) - lastProgressSaveSeconds) >= 15 else { return }
        lastProgressSaveSeconds = Double(positionSeconds)
        isSavingProgress = true
        defer { isSavingProgress = false }
        await appState.watchHistory.saveProgress(
            item: media,
            stream: stream,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        if !didMarkWatched && SharedCoreBridge.shouldMarkWatched(positionSeconds: positionSeconds, durationSeconds: durationSeconds) {
            didMarkWatched = true
            await appState.trakt.markWatched(item: media)
        }
    }

    private var preferredSubtitleLanguages: [String] {
        [
            appState.settings.profileSettings.defaultSubtitle,
            appState.settings.profileSettings.secondarySubtitle
        ].filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && normalized != "off" && normalized != "auto"
        }
    }

    private func preferredEmbeddedSubtitle(in group: AVMediaSelectionGroup) -> AVMediaSelectionOption? {
        let languages = preferredSubtitleLanguages
        guard !languages.isEmpty else { return nil }
        return group.options.first { option in
            languages.contains { preferred in
                Self.languageMatches(candidate: option.extendedLanguageTag ?? option.displayName, preferred: preferred) ||
                    Self.languageMatches(candidate: option.displayName, preferred: preferred)
            }
        }
    }

    private func autoSelectExternalSubtitleIfNeeded() async {
        guard selectedExternalSubtitleId == "off", externalSubtitleCues.isEmpty else { return }
        let languages = preferredSubtitleLanguages
        guard !languages.isEmpty else { return }
        guard let subtitle = stream.subtitles.first(where: { subtitle in
            languages.contains { preferred in
                Self.languageMatches(candidate: subtitle.language, preferred: preferred) ||
                    Self.languageMatches(candidate: subtitle.label, preferred: preferred)
            }
        }) else { return }
        await selectExternalSubtitle(subtitle)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let value = Int(seconds.rounded())
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private var captionFont: Font {
        switch appState.settings.profileSettings.subtitleSize {
        case "Small": return .system(size: 18, weight: subtitleWeight)
        case "Large": return .system(size: 28, weight: subtitleWeight)
        case "Extra Large": return .system(size: 34, weight: subtitleWeight)
        default: return .system(size: 23, weight: subtitleWeight)
        }
    }

    private var subtitleWeight: Font.Weight {
        appState.settings.profileSettings.subtitleStyle == "Regular" ? .regular : .bold
    }

    private var captionColor: Color {
        switch appState.settings.profileSettings.subtitleColor {
        case "Yellow": return .yellow
        case "Cyan": return .cyan
        case "Green": return .green
        default: return .white
        }
    }

    private var captionBackground: some ShapeStyle {
        appState.settings.profileSettings.subtitleStyle == "Shadow" ? Color.black.opacity(0.25) : Color.black.opacity(0.62)
    }

    private var captionBottomPadding: CGFloat {
        switch appState.settings.profileSettings.subtitleOffset {
        case "High": return 150
        case "Medium": return 100
        default: return 58
        }
    }

    private var aiTargetLanguage: String {
        let preferred = appState.settings.profileSettings.secondarySubtitle != "Off"
            ? appState.settings.profileSettings.secondarySubtitle
            : appState.settings.profileSettings.defaultSubtitle
        if preferred == "Off" || preferred == "Auto" { return "English" }
        return preferred
    }

    private static func parseSubtitleCues(_ raw: String) -> [ExternalSubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        return blocks.compactMap { block -> ExternalSubtitleCue? in
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("WEBVTT") }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseSubtitleTime(parts[0]),
                  let end = parseSubtitleTime(parts[1]) else { return nil }
            let text = lines.dropFirst(timingIndex + 1)
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ExternalSubtitleCue(start: start, end: end, text: text)
        }
    }

    private static func parseSubtitleTime(_ raw: String) -> Double? {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        let pieces = value.split(separator: ":").map(String.init)
        guard pieces.count >= 2 else { return nil }
        let seconds = Double(pieces.last ?? "") ?? 0
        let minutes = Double(pieces.dropLast().last ?? "") ?? 0
        let hours = pieces.count == 3 ? (Double(pieces.first ?? "") ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func languageMatches(candidate: String, preferred: String) -> Bool {
        let left = normalizeLanguage(candidate)
        let right = normalizeLanguage(preferred)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.hasPrefix("\(right)-") || right.hasPrefix("\(left)-")
    }

    private static func normalizeLanguage(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mapped = [
            "english": "en",
            "eng": "en",
            "dutch": "nl",
            "nederlands": "nl",
            "spanish": "es",
            "espanol": "es",
            "french": "fr",
            "german": "de",
            "italian": "it",
            "portuguese": "pt",
            "arabic": "ar",
            "turkish": "tr",
            "hindi": "hi",
            "japanese": "ja",
            "korean": "ko",
            "chinese": "zh"
        ]
        return mapped[value] ?? value
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .first ?? ""
    }

    private static func cleanHearingImpairedText(_ raw: String) -> String {
        raw
            .components(separatedBy: "\n")
            .map {
                $0.replacingOccurrences(of: #"\[[^\]]+\]|\([^\)]+\)"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
