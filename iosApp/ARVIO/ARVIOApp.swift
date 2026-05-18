import SwiftUI

@main
struct ARVIOApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .task {
                    await appState.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await appState.reloadCloudState()
                        if appState.trakt.isConnected {
                            await appState.trakt.loadWatchlist()
                        }
                        await appState.watchHistory.load()
                        await appState.catalogs.reloadRows()
                    }
                }
        }
    }
}
