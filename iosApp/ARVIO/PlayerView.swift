import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let stream: ResolvedStream
    @State private var player: AVPlayer?
    @State private var didSeek = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button("Close") {
                appState.selectedStream = nil
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
            player?.pause()
            player = nil
        }
    }
}
