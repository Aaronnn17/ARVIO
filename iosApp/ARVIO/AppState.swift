import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let auth: AuthService
    let cloud: CloudSyncService
    let addons: AddonService
    let trakt: TraktService
    let tmdb: TmdbService
    let streams: StreamResolver
    @Published var selectedMedia: MediaItem?
    @Published var selectedStream: ResolvedStream?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let auth = AuthService()
        let cloud = CloudSyncService(auth: auth)
        let addons = AddonService(cloud: cloud)
        let trakt = TraktService()
        let tmdb = TmdbService()
        let streams = StreamResolver(tmdb: tmdb, addons: addons)
        self.auth = auth
        self.cloud = cloud
        self.addons = addons
        self.trakt = trakt
        self.tmdb = tmdb
        self.streams = streams

        [auth.objectWillChange, cloud.objectWillChange, addons.objectWillChange, trakt.objectWillChange, tmdb.objectWillChange, streams.objectWillChange]
            .forEach { publisher in
                publisher
                    .sink { [weak self] _ in self?.objectWillChange.send() }
                    .store(in: &cancellables)
            }
    }

    func bootstrap() async {
        await auth.restore()
        await cloud.pull()
        addons.loadFromCloud()
        if trakt.isConnected {
            await trakt.loadWatchlist()
        }
        await tmdb.loadHome()
    }
}
