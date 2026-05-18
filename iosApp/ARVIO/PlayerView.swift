import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let stream: ResolvedStream
    @State private var player: AVPlayer?
    @State private var didSeek = false
    @State private var didSaveProgress = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button("Close") {
                Task { await closePlayer() }
            }
            .buttonStyle(.borderedProminent)
            .tint(ArvioTheme.gold)
            .padding(24)
        }
        .task(id: stream.id) {
            guard let url = stream.url else { return }
            let created = AVPlayer(url: url)
            player = created
            if let seconds = stream.resumePositionSeconds, seconds > 5, !didSeek {
                didSeek = true
                created.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600))
            }
            created.play()
        }
        .onDisappear {
            Task { await saveProgressIfNeeded() }
            player?.pause()
            player = nil
        }
    }

    private func closePlayer() async {
        await saveProgressIfNeeded()
        appState.selectedStream = nil
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
}
