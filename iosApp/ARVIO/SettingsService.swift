import Foundation

struct CloudProfileSettings: Codable, Equatable {
    var defaultSubtitle: String = "Off"
    var defaultAudioLanguage: String = "Auto (Original)"
    var contentLanguage: String = "en-US"
    var subtitleSize: String = "Medium"
    var subtitleColor: String = "White"
    var subtitleStyle: String = "Bold"
    var subtitleOffset: String = "Low"
    var subtitleStylized: Bool = true
    var cardLayoutMode: String = "Landscape"
    var frameRateMatchingMode: String = "Off"
    var autoPlayNext: Bool = true
    var autoPlaySingleSource: Bool = true
    var autoPlayMinQuality: String = "Any"
    var trailerAutoPlay: Bool = false
    var trailerSoundEnabled: Bool = false
    var clockFormat: String = "24h"
    var showBudget: Bool = true
    var spoilerBlurEnabled: Bool = false
    var volumeBoostDb: Int = 0
    var includeSpecials: Bool = false
    var dnsProvider: String = "system"
    var subtitleUsageJson: String = ""
    var subtitleSettingsUpdatedAt: Int64 = 0
    var iptvHiddenGroups: String = ""
    var iptvGroupOrder: String = ""
    var secondarySubtitle: String = "Off"
    var filterSubtitlesByLanguage: Bool = true
    var homeServerConnectionJson: String?
    var catalogueRowLayoutModes: [String: String] = [:]
}

struct GlobalCloudSettings: Codable, Equatable {
    var subtitleAiEnabled: Bool = false
    var subtitleAiAutoSelect: Bool = false
    var subtitleAiApiKey: String = ""
    var subtitleAiModel: String = "GROQ_LLAMA_70B"
    var subtitleRemoveHearingImpaired: Bool = true
    var skipProfileSelection: Bool = false
}

@MainActor
final class SettingsService: ObservableObject {
    @Published private(set) var profileSettings = CloudProfileSettings()
    @Published private(set) var globalSettings = GlobalCloudSettings()
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private var activeProfileId = "default"

    init(cloud: CloudSyncService) {
        self.cloud = cloud
    }

    func setActiveProfileId(_ profileId: String?) {
        let trimmed = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeProfileId = trimmed.isEmpty ? "default" : trimmed
        loadFromCloud()
    }

    func loadFromCloud() {
        if let byProfile = cloud.payload.profileSettingsById,
           let settings = byProfile[activeProfileId] ?? byProfile.values.first {
            profileSettings = settings
        } else {
            profileSettings = CloudProfileSettings(
                defaultSubtitle: cloud.payload.defaultSubtitle ?? "Off",
                defaultAudioLanguage: cloud.payload.defaultAudioLanguage ?? "Auto (Original)",
                cardLayoutMode: cloud.payload.cardLayoutMode ?? "Landscape",
                frameRateMatchingMode: cloud.payload.frameRateMatchingMode ?? "Off",
                autoPlayNext: cloud.payload.autoPlayNext ?? true,
                autoPlaySingleSource: cloud.payload.autoPlaySingleSource ?? true,
                autoPlayMinQuality: cloud.payload.autoPlayMinQuality ?? "Any",
                includeSpecials: cloud.payload.includeSpecials ?? false,
                dnsProvider: cloud.payload.dnsProvider ?? "system",
                subtitleUsageJson: cloud.payload.subtitleUsageJson ?? "",
                subtitleSettingsUpdatedAt: Int64(cloud.payload.subtitleSettingsUpdatedAt ?? 0)
            )
        }
        globalSettings = GlobalCloudSettings(
            subtitleAiEnabled: cloud.payload.subtitleAiEnabled ?? false,
            subtitleAiAutoSelect: cloud.payload.subtitleAiAutoSelect ?? false,
            subtitleAiApiKey: cloud.payload.subtitleAiApiKey ?? "",
            subtitleAiModel: cloud.payload.subtitleAiModel ?? "GROQ_LLAMA_70B",
            subtitleRemoveHearingImpaired: cloud.payload.subtitleRemoveHearingImpaired ?? true,
            skipProfileSelection: cloud.payload.skipProfileSelection ?? false
        )
    }

    func updateProfile(_ mutate: (inout CloudProfileSettings) -> Void) async {
        var updated = profileSettings
        mutate(&updated)
        updated.volumeBoostDb = min(max(updated.volumeBoostDb, 0), 15)
        updated.subtitleSettingsUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        profileSettings = updated
        await save()
    }

    func updateGlobal(_ mutate: (inout GlobalCloudSettings) -> Void) async {
        var updated = globalSettings
        mutate(&updated)
        globalSettings = updated
        await save()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await cloud.save(
            settings: profileSettings,
            globalSettings: globalSettings,
            profileId: activeProfileId
        )
        errorMessage = cloud.lastError
    }
}
