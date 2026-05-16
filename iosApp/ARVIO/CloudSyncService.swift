import Foundation

struct CloudPayload: Codable {
    var version: Int
    var addons: [InstalledAddon]
    var addonsByProfile: [String: [InstalledAddon]]?
    var activeProfileId: String?
    var profiles: [ArvioProfile]?
    var iptvByProfile: [String: IptvCloudProfileState]?
    var iptvM3uUrl: String?
    var iptvEpgUrl: String?
    var iptvFavoriteGroups: [String]?
    var iptvFavoriteChannels: [String]?
    var updatedAt: TimeInterval

    static let empty = CloudPayload(version: 1, addons: [], updatedAt: Date().timeIntervalSince1970)

    enum CodingKeys: String, CodingKey {
        case version
        case addons
        case addonsByProfile
        case activeProfileId
        case profiles
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

    private func save(
        addons: [InstalledAddon]?,
        addonProfileId: String? = nil,
        iptv: IptvCloudProfileState?,
        iptvProfileId: String? = nil,
        profiles: [ArvioProfile]? = nil,
        activeProfileId: String? = nil
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
