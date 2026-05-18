import Foundation

struct CloudPayload: Codable {
    var version: Int
    var addons: [InstalledAddon]
    var addonsByProfile: [String: [InstalledAddon]]? = nil
    var activeProfileId: String? = nil
    var profiles: [ArvioProfile]? = nil
    var traktTokens: [String: CloudTraktToken]? = nil
    var profileSettingsById: [String: CloudProfileSettings]? = nil
    var defaultSubtitle: String? = nil
    var defaultAudioLanguage: String? = nil
    var cardLayoutMode: String? = nil
    var frameRateMatchingMode: String? = nil
    var autoPlayNext: Bool? = nil
    var autoPlaySingleSource: Bool? = nil
    var autoPlayMinQuality: String? = nil
    var includeSpecials: Bool? = nil
    var dnsProvider: String? = nil
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

    static let empty = CloudPayload(version: 1, addons: [], updatedAt: Date().timeIntervalSince1970)

    enum CodingKeys: String, CodingKey {
        case version
        case addons
        case addonsByProfile
        case activeProfileId
        case profiles
        case traktTokens
        case profileSettingsById
        case defaultSubtitle
        case defaultAudioLanguage
        case cardLayoutMode
        case frameRateMatchingMode
        case autoPlayNext
        case autoPlaySingleSource
        case autoPlayMinQuality
        case includeSpecials
        case dnsProvider
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
        defaultSubtitle = try? container.decode(String.self, forKey: .defaultSubtitle)
        defaultAudioLanguage = try? container.decode(String.self, forKey: .defaultAudioLanguage)
        cardLayoutMode = try? container.decode(String.self, forKey: .cardLayoutMode)
        frameRateMatchingMode = try? container.decode(String.self, forKey: .frameRateMatchingMode)
        autoPlayNext = try? container.decode(Bool.self, forKey: .autoPlayNext)
        autoPlaySingleSource = try? container.decode(Bool.self, forKey: .autoPlaySingleSource)
        autoPlayMinQuality = try? container.decode(String.self, forKey: .autoPlayMinQuality)
        includeSpecials = try? container.decode(Bool.self, forKey: .includeSpecials)
        dnsProvider = try? container.decode(String.self, forKey: .dnsProvider)
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
    @Published var lastError: String?

    private let auth: AuthService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var rawPayloadObject: [String: Any] = [:]

    init(auth: AuthService) {
        self.auth = auth
    }

    func pull() async {
        guard let session = auth.session else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.accessToken()
            let rows: [AccountSyncRow] = try await auth.supabaseRequest(
                "/rest/v1/account_sync_state?user_id=eq.\(session.userId)&select=user_id,payload,updated_at",
                token: token
            )
            if let rawPayload = rows.first?.payload,
               let data = rawPayload.data(using: .utf8),
               let decoded = try? decoder.decode(CloudPayload.self, from: data) {
                payload = decoded
                rawPayloadObject = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
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

    func save(traktToken: CloudTraktToken?, profileId: String) async {
        await save(addons: nil, iptv: nil, traktToken: traktToken, traktProfileId: profileId)
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
        traktToken: CloudTraktToken? = nil,
        traktProfileId: String? = nil
    ) async {
        guard let session = auth.session else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.accessToken()
            var object = rawPayloadObject
            object["version"] = 1
            object["updatedAt"] = Date().timeIntervalSince1970
            if let addons {
                object["addons"] = try jsonObject(addons)
                if let addonProfileId {
                    var byProfile = object["addonsByProfile"] as? [String: Any] ?? [:]
                    byProfile[addonProfileId] = try jsonObject(addons)
                    object["addonsByProfile"] = byProfile
                }
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
                object["includeSpecials"] = settings.includeSpecials
                object["dnsProvider"] = settings.dnsProvider
                object["subtitleUsageJson"] = settings.subtitleUsageJson
                object["subtitleSettingsUpdatedAt"] = settings.subtitleSettingsUpdatedAt
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
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
