import Foundation

struct CloudPayload: Codable {
    var version: Int
    var addons: [InstalledAddon]
    var addonsByProfile: [String: [InstalledAddon]]? = nil
    var activeProfileId: String? = nil
    var profiles: [ArvioProfile]? = nil
    var traktTokens: [String: CloudTraktToken]? = nil
    var profileSettingsById: [String: CloudProfileSettings]? = nil
    var catalogsByProfile: [String: [CatalogConfig]]? = nil
    var catalogs: [CatalogConfig]? = nil
    var hiddenPreinstalledByProfile: [String: [String]]? = nil
    var hiddenPreinstalledCatalogs: [String]? = nil
    var watchlistByProfile: [String: [LocalWatchlistItem]]? = nil
    var dismissedContinueWatchingByProfile: [String: String]? = nil
    var localContinueWatchingByProfile: [String: [CloudContinueWatchingItem]]? = nil
    var localWatchedMoviesByProfile: [String: [Int]]? = nil
    var localWatchedEpisodesByProfile: [String: [String]]? = nil
    var hiddenAddonByProfile: [String: [String]]? = nil
    var hiddenHomeServerByProfile: [String: [String]]? = nil
    var defaultSubtitle: String? = nil
    var defaultAudioLanguage: String? = nil
    var cardLayoutMode: String? = nil
    var frameRateMatchingMode: String? = nil
    var autoPlayNext: Bool? = nil
    var autoPlaySingleSource: Bool? = nil
    var autoPlayMinQuality: String? = nil
    var trailerAutoPlay: Bool? = nil
    var trailerSoundEnabled: Bool? = nil
    var clockFormat: String? = nil
    var showBudget: Bool? = nil
    var includeSpecials: Bool? = nil
    var dnsProvider: String? = nil
    var customUserAgent: String? = nil
    var showLoadingStats: Bool? = nil
    var smoothScrolling: Bool? = nil
    var oledBlackBackground: Bool? = nil
    var spoilerBlurEnabled: Bool? = nil
    var accentColor: String? = nil
    var focusBorderColor: String? = nil
    var volumeBoostDb: Int? = nil
    var trailerDelaySeconds: Int? = nil
    var subtitleUsageJson: String? = nil
    var subtitleSettingsUpdatedAt: Int? = nil
    var skipProfileSelection: Bool? = nil
    var subtitleAiEnabled: Bool? = nil
    var subtitleAiAutoSelect: Bool? = nil
    var subtitleAiApiKey: String? = nil
    var subtitleAiModel: String? = nil
    var subtitleRemoveHearingImpaired: Bool? = nil
    var iptvByProfile: [String: IptvCloudProfileState]? = nil
    var iptvM3uUrl: String? = nil
    var iptvEpgUrl: String? = nil
    var iptvFavoriteGroups: [String]? = nil
    var iptvFavoriteChannels: [String]? = nil
    var updatedAt: TimeInterval

    static let empty = CloudPayload(version: 1, addons: [], updatedAt: Date().timeIntervalSince1970 * 1000)

    enum CodingKeys: String, CodingKey {
        case version
        case addons
        case addonsByProfile
        case activeProfileId
        case profiles
        case traktTokens
        case profileSettingsById
        case catalogsByProfile
        case catalogs
        case hiddenPreinstalledByProfile
        case hiddenPreinstalledCatalogs
        case watchlistByProfile
        case dismissedContinueWatchingByProfile
        case localContinueWatchingByProfile
        case localWatchedMoviesByProfile
        case localWatchedEpisodesByProfile
        case hiddenAddonByProfile
        case hiddenHomeServerByProfile
        case defaultSubtitle
        case defaultAudioLanguage
        case cardLayoutMode
        case frameRateMatchingMode
        case autoPlayNext
        case autoPlaySingleSource
        case autoPlayMinQuality
        case trailerAutoPlay
        case trailerSoundEnabled
        case clockFormat
        case showBudget
        case includeSpecials
        case dnsProvider
        case customUserAgent
        case showLoadingStats
        case smoothScrolling
        case oledBlackBackground
        case spoilerBlurEnabled
        case accentColor
        case focusBorderColor
        case volumeBoostDb
        case trailerDelaySeconds
        case subtitleUsageJson
        case subtitleSettingsUpdatedAt
        case skipProfileSelection
        case subtitleAiEnabled
        case subtitleAiAutoSelect
        case subtitleAiApiKey
        case subtitleAiModel
        case subtitleRemoveHearingImpaired
        case iptvByProfile
        case iptvM3uUrl
        case iptvEpgUrl
        case iptvFavoriteGroups
        case iptvFavoriteChannels
        case updatedAt
    }

    init(
        version: Int,
        addons: [InstalledAddon],
        addonsByProfile: [String: [InstalledAddon]]? = nil,
        activeProfileId: String? = nil,
        profiles: [ArvioProfile]? = nil,
        traktTokens: [String: CloudTraktToken]? = nil,
        profileSettingsById: [String: CloudProfileSettings]? = nil,
        catalogsByProfile: [String: [CatalogConfig]]? = nil,
        catalogs: [CatalogConfig]? = nil,
        hiddenPreinstalledByProfile: [String: [String]]? = nil,
        hiddenPreinstalledCatalogs: [String]? = nil,
        watchlistByProfile: [String: [LocalWatchlistItem]]? = nil,
        dismissedContinueWatchingByProfile: [String: String]? = nil,
        localContinueWatchingByProfile: [String: [CloudContinueWatchingItem]]? = nil,
        localWatchedMoviesByProfile: [String: [Int]]? = nil,
        localWatchedEpisodesByProfile: [String: [String]]? = nil,
        hiddenAddonByProfile: [String: [String]]? = nil,
        hiddenHomeServerByProfile: [String: [String]]? = nil,
        iptvByProfile: [String: IptvCloudProfileState]? = nil,
        iptvM3uUrl: String? = nil,
        iptvEpgUrl: String? = nil,
        iptvFavoriteGroups: [String]? = nil,
        iptvFavoriteChannels: [String]? = nil,
        updatedAt: TimeInterval
    ) {
        self.version = version
        self.addons = addons
        self.addonsByProfile = addonsByProfile
        self.activeProfileId = activeProfileId
        self.profiles = profiles
        self.traktTokens = traktTokens
        self.profileSettingsById = profileSettingsById
        self.catalogsByProfile = catalogsByProfile
        self.catalogs = catalogs
        self.hiddenPreinstalledByProfile = hiddenPreinstalledByProfile
        self.hiddenPreinstalledCatalogs = hiddenPreinstalledCatalogs
        self.watchlistByProfile = watchlistByProfile
        self.dismissedContinueWatchingByProfile = dismissedContinueWatchingByProfile
        self.localContinueWatchingByProfile = localContinueWatchingByProfile
        self.localWatchedMoviesByProfile = localWatchedMoviesByProfile
        self.localWatchedEpisodesByProfile = localWatchedEpisodesByProfile
        self.hiddenAddonByProfile = hiddenAddonByProfile
        self.hiddenHomeServerByProfile = hiddenHomeServerByProfile
        self.iptvByProfile = iptvByProfile
        self.iptvM3uUrl = iptvM3uUrl
        self.iptvEpgUrl = iptvEpgUrl
        self.iptvFavoriteGroups = iptvFavoriteGroups
        self.iptvFavoriteChannels = iptvFavoriteChannels
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        addons = (try? container.decode([InstalledAddon].self, forKey: .addons)) ?? []
        addonsByProfile = try? container.decode([String: [InstalledAddon]].self, forKey: .addonsByProfile)
        activeProfileId = try? container.decode(String.self, forKey: .activeProfileId)
        profiles = try? container.decode([ArvioProfile].self, forKey: .profiles)
        traktTokens = try? container.decode([String: CloudTraktToken].self, forKey: .traktTokens)
        profileSettingsById = try? container.decode([String: CloudProfileSettings].self, forKey: .profileSettingsById)
        catalogsByProfile = try? container.decode([String: [CatalogConfig]].self, forKey: .catalogsByProfile)
        catalogs = try? container.decode([CatalogConfig].self, forKey: .catalogs)
        hiddenPreinstalledByProfile = try? container.decode([String: [String]].self, forKey: .hiddenPreinstalledByProfile)
        hiddenPreinstalledCatalogs = try? container.decode([String].self, forKey: .hiddenPreinstalledCatalogs)
        watchlistByProfile = try? container.decode([String: [LocalWatchlistItem]].self, forKey: .watchlistByProfile)
        dismissedContinueWatchingByProfile = try? container.decode([String: String].self, forKey: .dismissedContinueWatchingByProfile)
        localContinueWatchingByProfile = try? container.decode([String: [CloudContinueWatchingItem]].self, forKey: .localContinueWatchingByProfile)
        localWatchedMoviesByProfile = try? container.decode([String: [Int]].self, forKey: .localWatchedMoviesByProfile)
        localWatchedEpisodesByProfile = try? container.decode([String: [String]].self, forKey: .localWatchedEpisodesByProfile)
        hiddenAddonByProfile = try? container.decode([String: [String]].self, forKey: .hiddenAddonByProfile)
        hiddenHomeServerByProfile = try? container.decode([String: [String]].self, forKey: .hiddenHomeServerByProfile)
        defaultSubtitle = try? container.decode(String.self, forKey: .defaultSubtitle)
        defaultAudioLanguage = try? container.decode(String.self, forKey: .defaultAudioLanguage)
        cardLayoutMode = try? container.decode(String.self, forKey: .cardLayoutMode)
        frameRateMatchingMode = try? container.decode(String.self, forKey: .frameRateMatchingMode)
        autoPlayNext = try? container.decode(Bool.self, forKey: .autoPlayNext)
        autoPlaySingleSource = try? container.decode(Bool.self, forKey: .autoPlaySingleSource)
        autoPlayMinQuality = try? container.decode(String.self, forKey: .autoPlayMinQuality)
        trailerAutoPlay = try? container.decode(Bool.self, forKey: .trailerAutoPlay)
        trailerSoundEnabled = try? container.decode(Bool.self, forKey: .trailerSoundEnabled)
        clockFormat = try? container.decode(String.self, forKey: .clockFormat)
        showBudget = try? container.decode(Bool.self, forKey: .showBudget)
        includeSpecials = try? container.decode(Bool.self, forKey: .includeSpecials)
        dnsProvider = try? container.decode(String.self, forKey: .dnsProvider)
        customUserAgent = try? container.decode(String.self, forKey: .customUserAgent)
        showLoadingStats = try? container.decode(Bool.self, forKey: .showLoadingStats)
        smoothScrolling = try? container.decode(Bool.self, forKey: .smoothScrolling)
        oledBlackBackground = try? container.decode(Bool.self, forKey: .oledBlackBackground)
        spoilerBlurEnabled = try? container.decode(Bool.self, forKey: .spoilerBlurEnabled)
        accentColor = try? container.decode(String.self, forKey: .accentColor)
        focusBorderColor = try? container.decode(String.self, forKey: .focusBorderColor)
        volumeBoostDb = try? container.decode(Int.self, forKey: .volumeBoostDb)
        trailerDelaySeconds = try? container.decode(Int.self, forKey: .trailerDelaySeconds)
        subtitleUsageJson = try? container.decode(String.self, forKey: .subtitleUsageJson)
        subtitleSettingsUpdatedAt = try? container.decode(Int.self, forKey: .subtitleSettingsUpdatedAt)
        skipProfileSelection = try? container.decode(Bool.self, forKey: .skipProfileSelection)
        subtitleAiEnabled = try? container.decode(Bool.self, forKey: .subtitleAiEnabled)
        subtitleAiAutoSelect = try? container.decode(Bool.self, forKey: .subtitleAiAutoSelect)
        subtitleAiApiKey = try? container.decode(String.self, forKey: .subtitleAiApiKey)
        subtitleAiModel = try? container.decode(String.self, forKey: .subtitleAiModel)
        subtitleRemoveHearingImpaired = try? container.decode(Bool.self, forKey: .subtitleRemoveHearingImpaired)
        iptvByProfile = try? container.decode([String: IptvCloudProfileState].self, forKey: .iptvByProfile)
        iptvM3uUrl = try? container.decode(String.self, forKey: .iptvM3uUrl)
        iptvEpgUrl = try? container.decode(String.self, forKey: .iptvEpgUrl)
        iptvFavoriteGroups = try? container.decode([String].self, forKey: .iptvFavoriteGroups)
        iptvFavoriteChannels = try? container.decode([String].self, forKey: .iptvFavoriteChannels)
        updatedAt = (try? container.decode(TimeInterval.self, forKey: .updatedAt)) ?? Date().timeIntervalSince1970
    }
}

private struct AccountSyncRow: Codable {
    let userId: String?
    let payload: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case payload
        case updatedAt = "updated_at"
    }
}

private struct AccountSyncUpsert: Codable {
    let userId: String
    let payload: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case payload
        case updatedAt = "updated_at"
    }
}

@MainActor
final class CloudSyncService: ObservableObject {
    @Published private(set) var payload = CloudPayload.empty
    @Published private(set) var isSyncing = false
    @Published private(set) var isPushDirty = false
    @Published var lastError: String?

    private let auth: AuthService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var rawPayloadObject: [String: Any] = [:]
    private let localDirtyAtKey = "arvio.ios.cloudSync.localDirtyAt"
    private let lastAppliedAtKey = "arvio.ios.cloudSync.lastAppliedAt"

    init(auth: AuthService) {
        self.auth = auth
        isPushDirty = UserDefaults.standard.double(forKey: localDirtyAtKey) > 0
    }

    func pull() async {
        guard let session = auth.session else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.accessToken()
            if let remote = try await fetchRemoteState(session: session, token: token) {
                payload = remote.payload
                rawPayloadObject = remote.object
                markCloudPayloadApplied(remote.payload.updatedAt)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save(addons: [InstalledAddon], profileId: String?) async {
        await save(addons: addons, addonProfileId: profileId, iptv: nil)
    }

    func save(iptv: IptvCloudProfileState, profileId: String) async {
        await save(addons: nil, iptv: iptv, iptvProfileId: profileId)
    }

    func save(profiles: [ArvioProfile], activeProfileId: String?) async {
        await save(addons: nil, iptv: nil, profiles: profiles, activeProfileId: activeProfileId)
    }

    func save(settings: CloudProfileSettings, globalSettings: GlobalCloudSettings, profileId: String) async {
        await save(addons: nil, iptv: nil, settings: settings, globalSettings: globalSettings, settingsProfileId: profileId)
    }

    func save(catalogs: [CatalogConfig], hiddenPreinstalledCatalogIds: [String], profileId: String) async {
        await save(addons: nil, iptv: nil, catalogs: catalogs, hiddenPreinstalledCatalogIds: hiddenPreinstalledCatalogIds, catalogsProfileId: profileId)
    }

    func save(traktToken: CloudTraktToken?, profileId: String) async {
        await save(addons: nil, iptv: nil, traktToken: traktToken, traktProfileId: profileId)
    }

    func save(watchlist: [LocalWatchlistItem], profileId: String) async {
        await save(addons: nil, iptv: nil, watchlist: watchlist, watchlistProfileId: profileId)
    }

    func save(dismissedContinueWatchingRaw: String, profileId: String) async {
        await save(
            addons: nil,
            iptv: nil,
            dismissedContinueWatchingRaw: dismissedContinueWatchingRaw,
            dismissedContinueWatchingProfileId: profileId
        )
    }

    func save(localContinueWatching: [CloudContinueWatchingItem], profileId: String) async {
        await save(
            addons: nil,
            iptv: nil,
            localContinueWatching: localContinueWatching,
            localContinueWatchingProfileId: profileId
        )
    }

    func save(localWatchedMovies: [Int], localWatchedEpisodes: [String], profileId: String) async {
        await save(
            addons: nil,
            iptv: nil,
            localWatchedMovies: localWatchedMovies,
            localWatchedEpisodes: localWatchedEpisodes,
            localWatchedProfileId: profileId
        )
    }

    private func save(
        addons: [InstalledAddon]?,
        addonProfileId: String? = nil,
        iptv: IptvCloudProfileState?,
        iptvProfileId: String? = nil,
        profiles: [ArvioProfile]? = nil,
        activeProfileId: String? = nil,
        settings: CloudProfileSettings? = nil,
        globalSettings: GlobalCloudSettings? = nil,
        settingsProfileId: String? = nil,
        catalogs: [CatalogConfig]? = nil,
        hiddenPreinstalledCatalogIds: [String]? = nil,
        catalogsProfileId: String? = nil,
        traktToken: CloudTraktToken? = nil,
        traktProfileId: String? = nil,
        watchlist: [LocalWatchlistItem]? = nil,
        watchlistProfileId: String? = nil,
        dismissedContinueWatchingRaw: String? = nil,
        dismissedContinueWatchingProfileId: String? = nil,
        localContinueWatching: [CloudContinueWatchingItem]? = nil,
        localContinueWatchingProfileId: String? = nil,
        localWatchedMovies: [Int]? = nil,
        localWatchedEpisodes: [String]? = nil,
        localWatchedProfileId: String? = nil
    ) async {
        guard let session = auth.session else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.accessToken()
            if let remote = try await fetchRemoteState(session: session, token: token) {
                payload = remote.payload
                rawPayloadObject = remote.object
            }
            var object = rawPayloadObject
            object["version"] = 1
            object["updatedAt"] = Int64(Date().timeIntervalSince1970 * 1000)
            if let addons {
                object["addons"] = try jsonObject(addons)
                var byProfile = object["addonsByProfile"] as? [String: Any] ?? [:]
                for profileId in profileIds(in: object, fallback: addonProfileId ?? session.userId) {
                    byProfile[profileId] = try jsonObject(addons)
                }
                object["addonsByProfile"] = byProfile
            }
            if let iptv {
                object["iptvM3uUrl"] = iptv.m3uUrl
                object["iptvEpgUrl"] = iptv.epgUrl
                object["iptvFavoriteGroups"] = iptv.favoriteGroups
                object["iptvFavoriteChannels"] = iptv.favoriteChannels
                var byProfile = object["iptvByProfile"] as? [String: Any] ?? [:]
                byProfile[iptvProfileId ?? session.userId] = try jsonObject(iptv)
                object["iptvByProfile"] = byProfile
            }
            if let profiles {
                object["profiles"] = try jsonObject(profiles)
                if let activeProfileId = activeProfileId ?? profiles.first?.id {
                    object["activeProfileId"] = activeProfileId
                } else {
                    object["activeProfileId"] = NSNull()
                }
            }
            if let traktProfileId {
                var tokens = object["traktTokens"] as? [String: Any] ?? [:]
                if let traktToken {
                    tokens[traktProfileId] = try jsonObject(traktToken)
                } else {
                    tokens.removeValue(forKey: traktProfileId)
                }
                object["traktTokens"] = tokens
            }
            if let watchlist {
                let profileId = watchlistProfileId ?? session.userId
                var byProfile = object["watchlistByProfile"] as? [String: Any] ?? [:]
                byProfile[profileId] = try jsonObject(watchlist)
                object["watchlistByProfile"] = byProfile
            }
            if let dismissedContinueWatchingRaw {
                let profileId = dismissedContinueWatchingProfileId ?? session.userId
                var byProfile = object["dismissedContinueWatchingByProfile"] as? [String: Any] ?? [:]
                if dismissedContinueWatchingRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    byProfile.removeValue(forKey: profileId)
                } else {
                    byProfile[profileId] = dismissedContinueWatchingRaw
                }
                object["dismissedContinueWatchingByProfile"] = byProfile
            }
            if let localContinueWatching {
                let profileId = localContinueWatchingProfileId ?? session.userId
                var byProfile = object["localContinueWatchingByProfile"] as? [String: Any] ?? [:]
                byProfile[profileId] = try jsonObject(localContinueWatching)
                object["localContinueWatchingByProfile"] = byProfile
            }
            if localWatchedMovies != nil || localWatchedEpisodes != nil {
                let profileId = localWatchedProfileId ?? session.userId
                if let localWatchedMovies {
                    var byProfile = object["localWatchedMoviesByProfile"] as? [String: Any] ?? [:]
                    byProfile[profileId] = localWatchedMovies
                    object["localWatchedMoviesByProfile"] = byProfile
                }
                if let localWatchedEpisodes {
                    var byProfile = object["localWatchedEpisodesByProfile"] as? [String: Any] ?? [:]
                    byProfile[profileId] = localWatchedEpisodes
                    object["localWatchedEpisodesByProfile"] = byProfile
                }
            }
            if let settings {
                let profileId = settingsProfileId ?? session.userId
                var byProfile = object["profileSettingsById"] as? [String: Any] ?? [:]
                byProfile[profileId] = try jsonObject(settings)
                object["profileSettingsById"] = byProfile
                object["defaultSubtitle"] = settings.defaultSubtitle
                object["defaultAudioLanguage"] = settings.defaultAudioLanguage
                object["cardLayoutMode"] = settings.cardLayoutMode
                object["frameRateMatchingMode"] = settings.frameRateMatchingMode
                object["autoPlayNext"] = settings.autoPlayNext
                object["autoPlaySingleSource"] = settings.autoPlaySingleSource
                object["autoPlayMinQuality"] = settings.autoPlayMinQuality
                object["trailerAutoPlay"] = settings.trailerAutoPlay
                object["trailerSoundEnabled"] = settings.trailerSoundEnabled
                object["trailerDelaySeconds"] = settings.trailerDelaySeconds
                object["clockFormat"] = settings.clockFormat
                object["showBudget"] = settings.showBudget
                object["includeSpecials"] = settings.includeSpecials
                object["dnsProvider"] = settings.dnsProvider
                object["customUserAgent"] = settings.customUserAgent
                object["showLoadingStats"] = settings.showLoadingStats
                object["smoothScrolling"] = settings.smoothScrolling
                object["oledBlackBackground"] = settings.oledBlackBackground
                object["spoilerBlurEnabled"] = settings.spoilerBlurEnabled
                object["accentColor"] = settings.accentColor
                object["focusBorderColor"] = settings.accentColor
                object["volumeBoostDb"] = settings.volumeBoostDb
                object["subtitleUsageJson"] = settings.subtitleUsageJson
                object["subtitleSettingsUpdatedAt"] = settings.subtitleSettingsUpdatedAt
            }
            if let catalogs {
                let profileId = catalogsProfileId ?? session.userId
                var byProfile = object["catalogsByProfile"] as? [String: Any] ?? [:]
                byProfile[profileId] = try jsonObject(catalogs)
                object["catalogsByProfile"] = byProfile
                object["catalogs"] = try jsonObject(catalogs)
                if let hiddenPreinstalledCatalogIds {
                    var hiddenByProfile = object["hiddenPreinstalledByProfile"] as? [String: Any] ?? [:]
                    hiddenByProfile[profileId] = hiddenPreinstalledCatalogIds
                    object["hiddenPreinstalledByProfile"] = hiddenByProfile
                    object["hiddenPreinstalledCatalogs"] = hiddenPreinstalledCatalogIds
                }
            }
            if let globalSettings {
                object["subtitleAiEnabled"] = globalSettings.subtitleAiEnabled
                object["subtitleAiAutoSelect"] = globalSettings.subtitleAiAutoSelect
                object["subtitleAiApiKey"] = globalSettings.subtitleAiApiKey
                object["subtitleAiModel"] = globalSettings.subtitleAiModel
                object["subtitleRemoveHearingImpaired"] = globalSettings.subtitleRemoveHearingImpaired
                object["skipProfileSelection"] = globalSettings.skipProfileSelection
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let raw = String(data: data, encoding: .utf8) ?? "{}"
            let body = AccountSyncUpsert(
                userId: session.userId,
                payload: raw,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            let _: EmptyResponse = try await auth.supabaseRequest(
                "/rest/v1/account_sync_state",
                method: "POST",
                token: token,
                prefer: "return=minimal,resolution=merge-duplicates",
                body: body
            )
            rawPayloadObject = object
            payload = (try? decoder.decode(CloudPayload.self, from: data)) ?? payload
            markCloudPayloadApplied(payload.updatedAt)
            clearLocalDirty()
            lastError = nil
        } catch {
            markLocalDirty()
            lastError = error.localizedDescription
        }
    }

    private func fetchRemoteState(session: AuthSession, token: String) async throws -> (payload: CloudPayload, object: [String: Any])? {
        let rows: [AccountSyncRow] = try await auth.supabaseRequest(
            "/rest/v1/account_sync_state?user_id=eq.\(session.userId)&select=user_id,payload,updated_at",
            token: token
        )
        guard let rawPayload = rows.first?.payload,
              let data = rawPayload.data(using: .utf8),
              let decoded = try? decoder.decode(CloudPayload.self, from: data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (decoded, object)
    }

    private func markLocalDirty() {
        let dirtyAt = Date().timeIntervalSince1970 * 1000
        isPushDirty = true
        UserDefaults.standard.set(dirtyAt, forKey: localDirtyAtKey)
    }

    private func clearLocalDirty() {
        isPushDirty = false
        UserDefaults.standard.removeObject(forKey: localDirtyAtKey)
    }

    private func markCloudPayloadApplied(_ updatedAt: TimeInterval) {
        UserDefaults.standard.set(updatedAt, forKey: lastAppliedAtKey)
    }

    private func profileIds(in object: [String: Any], fallback: String) -> [String] {
        let profiles = object["profiles"] as? [[String: Any]] ?? []
        var ids = profiles.compactMap { ($0["id"] as? String)?.nilIfBlank }
        if ids.isEmpty, let decoded = try? JSONSerialization.data(withJSONObject: object["profiles"] ?? []) {
            let restored = try? decoder.decode([ArvioProfile].self, from: decoded)
            ids = restored?.compactMap { $0.id.nilIfBlank } ?? []
        }
        if ids.isEmpty {
            ids = [fallback]
        }
        return Array(Set(ids)).sorted()
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
