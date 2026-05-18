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

    enum CodingKeys: String, CodingKey {
        case defaultSubtitle
        case defaultAudioLanguage
        case contentLanguage
        case subtitleSize
        case subtitleColor
        case subtitleStyle
        case subtitleOffset
        case subtitleStylized
        case cardLayoutMode
        case frameRateMatchingMode
        case autoPlayNext
        case autoPlaySingleSource
        case autoPlayMinQuality
        case trailerAutoPlay
        case trailerSoundEnabled
        case clockFormat
        case showBudget
        case spoilerBlurEnabled
        case volumeBoostDb
        case includeSpecials
        case dnsProvider
        case subtitleUsageJson
        case subtitleSettingsUpdatedAt
        case iptvHiddenGroups
        case iptvGroupOrder
        case secondarySubtitle
        case filterSubtitlesByLanguage
        case homeServerConnectionJson
        case catalogueRowLayoutModes
    }

    init() {}

    init(
        defaultSubtitle: String = "Off",
        defaultAudioLanguage: String = "Auto (Original)",
        contentLanguage: String = "en-US",
        subtitleSize: String = "Medium",
        subtitleColor: String = "White",
        subtitleStyle: String = "Bold",
        subtitleOffset: String = "Low",
        subtitleStylized: Bool = true,
        cardLayoutMode: String = "Landscape",
        frameRateMatchingMode: String = "Off",
        autoPlayNext: Bool = true,
        autoPlaySingleSource: Bool = true,
        autoPlayMinQuality: String = "Any",
        trailerAutoPlay: Bool = false,
        trailerSoundEnabled: Bool = false,
        clockFormat: String = "24h",
        showBudget: Bool = true,
        spoilerBlurEnabled: Bool = false,
        volumeBoostDb: Int = 0,
        includeSpecials: Bool = false,
        dnsProvider: String = "system",
        subtitleUsageJson: String = "",
        subtitleSettingsUpdatedAt: Int64 = 0,
        iptvHiddenGroups: String = "",
        iptvGroupOrder: String = "",
        secondarySubtitle: String = "Off",
        filterSubtitlesByLanguage: Bool = true,
        homeServerConnectionJson: String? = nil,
        catalogueRowLayoutModes: [String: String] = [:]
    ) {
        self.defaultSubtitle = defaultSubtitle
        self.defaultAudioLanguage = defaultAudioLanguage
        self.contentLanguage = contentLanguage
        self.subtitleSize = subtitleSize
        self.subtitleColor = subtitleColor
        self.subtitleStyle = subtitleStyle
        self.subtitleOffset = subtitleOffset
        self.subtitleStylized = subtitleStylized
        self.cardLayoutMode = cardLayoutMode
        self.frameRateMatchingMode = frameRateMatchingMode
        self.autoPlayNext = autoPlayNext
        self.autoPlaySingleSource = autoPlaySingleSource
        self.autoPlayMinQuality = autoPlayMinQuality
        self.trailerAutoPlay = trailerAutoPlay
        self.trailerSoundEnabled = trailerSoundEnabled
        self.clockFormat = clockFormat
        self.showBudget = showBudget
        self.spoilerBlurEnabled = spoilerBlurEnabled
        self.volumeBoostDb = volumeBoostDb
        self.includeSpecials = includeSpecials
        self.dnsProvider = dnsProvider
        self.subtitleUsageJson = subtitleUsageJson
        self.subtitleSettingsUpdatedAt = subtitleSettingsUpdatedAt
        self.iptvHiddenGroups = iptvHiddenGroups
        self.iptvGroupOrder = iptvGroupOrder
        self.secondarySubtitle = secondarySubtitle
        self.filterSubtitlesByLanguage = filterSubtitlesByLanguage
        self.homeServerConnectionJson = homeServerConnectionJson
        self.catalogueRowLayoutModes = catalogueRowLayoutModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultSubtitle = (try? container.decode(String.self, forKey: .defaultSubtitle)) ?? "Off"
        defaultAudioLanguage = (try? container.decode(String.self, forKey: .defaultAudioLanguage)) ?? "Auto (Original)"
        contentLanguage = (try? container.decode(String.self, forKey: .contentLanguage)) ?? "en-US"
        subtitleSize = (try? container.decode(String.self, forKey: .subtitleSize)) ?? "Medium"
        subtitleColor = (try? container.decode(String.self, forKey: .subtitleColor)) ?? "White"
        subtitleStyle = (try? container.decode(String.self, forKey: .subtitleStyle)) ?? "Bold"
        subtitleOffset = (try? container.decode(String.self, forKey: .subtitleOffset)) ?? "Low"
        subtitleStylized = (try? container.decode(Bool.self, forKey: .subtitleStylized)) ?? true
        cardLayoutMode = (try? container.decode(String.self, forKey: .cardLayoutMode)) ?? "Landscape"
        frameRateMatchingMode = (try? container.decode(String.self, forKey: .frameRateMatchingMode)) ?? "Off"
        autoPlayNext = (try? container.decode(Bool.self, forKey: .autoPlayNext)) ?? true
        autoPlaySingleSource = (try? container.decode(Bool.self, forKey: .autoPlaySingleSource)) ?? true
        autoPlayMinQuality = (try? container.decode(String.self, forKey: .autoPlayMinQuality)) ?? "Any"
        trailerAutoPlay = (try? container.decode(Bool.self, forKey: .trailerAutoPlay)) ?? false
        trailerSoundEnabled = (try? container.decode(Bool.self, forKey: .trailerSoundEnabled)) ?? false
        clockFormat = (try? container.decode(String.self, forKey: .clockFormat)) ?? "24h"
        showBudget = (try? container.decode(Bool.self, forKey: .showBudget)) ?? true
        spoilerBlurEnabled = (try? container.decode(Bool.self, forKey: .spoilerBlurEnabled)) ?? false
        volumeBoostDb = (try? container.decode(Int.self, forKey: .volumeBoostDb)) ?? 0
        includeSpecials = (try? container.decode(Bool.self, forKey: .includeSpecials)) ?? false
        dnsProvider = (try? container.decode(String.self, forKey: .dnsProvider)) ?? "system"
        subtitleUsageJson = (try? container.decode(String.self, forKey: .subtitleUsageJson)) ?? ""
        if let intValue = try? container.decode(Int64.self, forKey: .subtitleSettingsUpdatedAt) {
            subtitleSettingsUpdatedAt = intValue
        } else {
            subtitleSettingsUpdatedAt = Int64((try? container.decode(Int.self, forKey: .subtitleSettingsUpdatedAt)) ?? 0)
        }
        iptvHiddenGroups = (try? container.decode(String.self, forKey: .iptvHiddenGroups)) ?? ""
        iptvGroupOrder = (try? container.decode(String.self, forKey: .iptvGroupOrder)) ?? ""
        secondarySubtitle = (try? container.decode(String.self, forKey: .secondarySubtitle)) ?? "Off"
        filterSubtitlesByLanguage = (try? container.decode(Bool.self, forKey: .filterSubtitlesByLanguage)) ?? true
        homeServerConnectionJson = try? container.decode(String.self, forKey: .homeServerConnectionJson)
        catalogueRowLayoutModes = (try? container.decode([String: String].self, forKey: .catalogueRowLayoutModes)) ?? [:]
    }
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
