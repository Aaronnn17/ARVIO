import AVKit
import Combine
import SwiftUI

private struct PlayerTrackOption: Identifiable {
    let id: String
    let title: String
    let option: AVMediaSelectionOption?
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
    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    private let progressTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            Color.black.opacity(showControls ? 0.24 : 0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showControls.toggle()
                    }
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
            let asset = stream.requestHeaders.isEmpty
                ? AVURLAsset(url: url)
                : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.requestHeaders])
            let created = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = created
            if let seconds = stream.resumePositionSeconds, seconds > 5, !didSeek {
                didSeek = true
                created.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600))
            }
            created.play()
            isPlaying = true
            loadTrackOptions(from: created.currentItem)
        }
        .onReceive(progressTimer) { _ in updateProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item == player?.currentItem else { return }
            Task { await handlePlaybackEnded() }
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
                Button(showSources ? "Hide Sources" : "Sources") { showSources.toggle() }
                    .buttonStyle(.bordered)
                Button(showTracks ? "Hide Tracks" : "Tracks") { showTracks.toggle() }
                    .buttonStyle(.bordered)
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

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func updateProgress() {
        guard let player else { return }
        let current = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        if current.isFinite { currentSeconds = current }
        if duration.isFinite && duration > 0 { durationSeconds = duration }
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
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
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
        }
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
        guard !didSaveProgress, let media = appState.selectedMedia, let player else { return }
        let current = player.currentTime().seconds
        let rawDuration = player.currentItem?.duration.seconds ?? 0
        let fallbackDuration = Double(media.durationSeconds ?? 0)
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : fallbackDuration
        guard current.isFinite, current > 5, duration > 30 else { return }
        didSaveProgress = true
        await appState.watchHistory.saveProgress(
            item: media,
            stream: stream,
            positionSeconds: Int(current.rounded()),
            durationSeconds: Int(duration.rounded())
        )
        if current / duration >= 0.9 {
            await appState.trakt.markWatched(item: media)
        } else {
            try? await appState.trakt.scrobblePause(item: media, progressPercent: (current / duration) * 100)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let value = Int(seconds.rounded())
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
