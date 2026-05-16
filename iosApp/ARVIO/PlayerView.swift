import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let stream: ResolvedStream

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = stream.url {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
            Button("Close") {
                appState.selectedStream = nil
            }
            .buttonStyle(.borderedProminent)
            .tint(ArvioTheme.gold)
            .padding(24)
        }
    }
}
