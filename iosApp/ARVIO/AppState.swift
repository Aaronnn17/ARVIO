import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let auth: AuthService
    let cloud: CloudSyncService
    let addons: AddonService
    let trakt: TraktService
    let tmdb: TmdbService
    let catalogs: CatalogService
    let streams: StreamResolver
    let iptv: IptvService
    let profiles: ProfileService
    let watchHistory: WatchHistoryService
    let settings: SettingsService
    @Published var selectedMedia: MediaItem?
    @Published var selectedStream: ResolvedStream?
    @Published var selectedCatalog: CatalogConfig?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let auth = AuthService()
        let cloud = CloudSyncService(auth: auth)
        let addons = AddonService(cloud: cloud)
        let trakt = TraktService(cloud: cloud)
        let tmdb = TmdbService()
        let catalogs = CatalogService(cloud: cloud, tmdb: tmdb, addons: addons)
        let streams = StreamResolver(tmdb: tmdb, addons: addons)
        let iptv = IptvService(cloud: cloud)
        let profiles = ProfileService(cloud: cloud)
        let watchHistory = WatchHistoryService(auth: auth, trakt: trakt)
        let settings = SettingsService(cloud: cloud)
        self.auth = auth
        self.cloud = cloud
        self.addons = addons
        self.trakt = trakt
        self.tmdb = tmdb
        self.catalogs = catalogs
        self.streams = streams
        self.iptv = iptv
        self.profiles = profiles
        self.watchHistory = watchHistory
        self.settings = settings
        profiles.onActiveProfileChanged = { profileId in
            addons.setActiveProfileId(profileId)
            catalogs.setActiveProfileId(profileId)
            trakt.setActiveProfileId(profileId)
            iptv.setActiveProfileId(profileId)
            watchHistory.setActiveProfileId(profileId)
            settings.setActiveProfileId(profileId)
            Task { await watchHistory.load() }
        }

        [auth.objectWillChange, cloud.objectWillChange, addons.objectWillChange, catalogs.objectWillChange, trakt.objectWillChange, tmdb.objectWillChange, streams.objectWillChange, iptv.objectWillChange, profiles.objectWillChange, watchHistory.objectWillChange, settings.objectWillChange]
            .forEach { publisher in
                publisher
                    .sink { [weak self] _ in self?.objectWillChange.send() }
                    .store(in: &cancellables)
            }
    }

    func bootstrap() async {
        await auth.restore()
        await reloadCloudState()
        if trakt.isConnected {
            await trakt.loadWatchlist()
        }
        await watchHistory.load()
        await tmdb.loadHome()
        await catalogs.reloadRows()
    }

    func reloadCloudState() async {
        await cloud.pull()
        profiles.loadFromCloud()
        profiles.ensureDefault(email: auth.session?.email)
        let profileId = profiles.activeProfile?.id
        addons.setActiveProfileId(profileId)
        catalogs.setActiveProfileId(profileId)
        trakt.setActiveProfileId(profileId)
        iptv.setActiveProfileId(profileId)
        watchHistory.setActiveProfileId(profileId)
        settings.setActiveProfileId(profileId)
    }
}
