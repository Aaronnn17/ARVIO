import Foundation

struct ArvioProfile: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatarColor: Int64
    var avatarId: Int
    var avatarImageVersion: Int64
    var avatarImageStoragePath: String?
    var isKidsProfile: Bool
    var pin: String?
    var isLocked: Bool
    var createdAt: Int64
    var lastUsedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarColor
        case avatarId
        case avatarImageVersion
        case avatarImageStoragePath
        case isKidsProfile
        case pin
        case isLocked
        case createdAt
        case lastUsedAt
    }

    static func make(name: String, color: Int64 = 0xFF3B82F6) -> ArvioProfile {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ArvioProfile(
            id: UUID().uuidString,
            name: name,
            avatarColor: color,
            avatarId: 0,
            avatarImageVersion: 0,
            avatarImageStoragePath: nil,
            isKidsProfile: false,
            pin: nil,
            isLocked: false,
            createdAt: now,
            lastUsedAt: now
        )
    }

    var swiftUIColorHex: String {
        let masked = avatarColor & 0x00FF_FFFF
        return String(format: "#%06llX", masked)
    }
}

@MainActor
final class ProfileService: ObservableObject {
    @Published private(set) var profiles: [ArvioProfile] = []
    @Published private(set) var activeProfileId: String?
    @Published var isSwitcherVisible = false
    @Published var newProfileName = ""
    @Published var pinEntry = ""
    @Published var pendingLockedProfile: ArvioProfile?
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let storageKey = "arvio.ios.profiles"
    private let activeKey = "arvio.ios.activeProfileId"
    var onActiveProfileChanged: ((String?) -> Void)?
    private let avatarColors: [Int64] = [0xFFE50914, 0xFF1DB954, 0xFF3B82F6, 0xFFF59E0B, 0xFF8B5CF6, 0xFFEC4899, 0xFF14B8A6, 0xFF6366F1]

    init(cloud: CloudSyncService) {
        self.cloud = cloud
        loadLocal()
    }

    var activeProfile: ArvioProfile? {
        profiles.first { $0.id == activeProfileId } ?? profiles.first
    }

    func ensureDefault(email: String?) {
        guard profiles.isEmpty else { return }
        profiles = [ArvioProfile.make(name: email?.split(separator: "@").first.map(String.init) ?? "ARVIO")]
        activeProfileId = profiles.first?.id
        onActiveProfileChanged?(activeProfileId)
        saveLocal()
    }

    func loadFromCloud() {
        if let cloudProfiles = cloud.payload.profiles, !cloudProfiles.isEmpty {
            profiles = cloudProfiles
            activeProfileId = cloud.payload.activeProfileId ?? activeProfileId ?? cloudProfiles.first?.id
            onActiveProfileChanged?(activeProfileId)
            saveLocal()
        }
    }

    func createProfile() async {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Profile name is required"
            return
        }
        profiles.append(ArvioProfile.make(name: name, color: avatarColors[profiles.count % avatarColors.count]))
        newProfileName = ""
        errorMessage = nil
        saveLocal()
        await cloud.save(profiles: profiles, activeProfileId: activeProfileId)
    }

    func requestSelect(_ profile: ArvioProfile) {
        if profile.isLocked {
            pendingLockedProfile = profile
            pinEntry = ""
        } else {
            select(profile)
        }
    }

    func confirmPin() {
        guard let profile = pendingLockedProfile else { return }
        guard profile.pin == pinEntry else {
            errorMessage = "Incorrect PIN"
            return
        }
        pendingLockedProfile = nil
        pinEntry = ""
        select(profile)
    }

    func select(_ profile: ArvioProfile) {
        activeProfileId = profile.id
        onActiveProfileChanged?(profile.id)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].lastUsedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }
        isSwitcherVisible = false
        errorMessage = nil
        saveLocal()
        Task { await cloud.save(profiles: profiles, activeProfileId: profile.id) }
    }

    func delete(_ profile: ArvioProfile) async {
        guard profiles.count > 1 else {
            errorMessage = "At least one profile is required"
            return
        }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
            onActiveProfileChanged?(activeProfileId)
        }
        saveLocal()
        await cloud.save(profiles: profiles, activeProfileId: activeProfileId)
    }

    func renameActive(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = activeProfileIndex else { return }
        profiles[index].name = trimmed
        await saveProfiles()
    }

    func setActiveKidsProfile(_ isKids: Bool) async {
        guard let index = activeProfileIndex else { return }
        profiles[index].isKidsProfile = isKids
        await saveProfiles()
    }

    func setActivePin(_ pin: String) async {
        guard let index = activeProfileIndex else { return }
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].pin = trimmed.isEmpty ? nil : trimmed
        profiles[index].isLocked = !trimmed.isEmpty
        await saveProfiles()
    }

    func cycleActiveAvatarColor() async {
        guard let index = activeProfileIndex else { return }
        let current = profiles[index].avatarColor
        let nextIndex = ((avatarColors.firstIndex(of: current) ?? -1) + 1) % avatarColors.count
        profiles[index].avatarColor = avatarColors[nextIndex]
        profiles[index].avatarId = nextIndex
        profiles[index].avatarImageVersion = Int64(Date().timeIntervalSince1970 * 1000)
        await saveProfiles()
    }

    private var activeProfileIndex: Int? {
        guard let active = activeProfile else { return nil }
        return profiles.firstIndex(where: { $0.id == active.id })
    }

    private func saveProfiles() async {
        errorMessage = nil
        saveLocal()
        await cloud.save(profiles: profiles, activeProfileId: activeProfileId)
    }

    private func loadLocal() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ArvioProfile].self, from: data) {
            profiles = decoded
        }
        activeProfileId = UserDefaults.standard.string(forKey: activeKey)
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(activeProfileId, forKey: activeKey)
    }
}
