import Foundation

struct InstalledAddon: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let manifestURL: String
    let description: String?
    let catalogs: [String]
    let resources: [String]
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case manifestURL
        case description
        case catalogs
        case resources
        case isEnabled
        case enabled
        case url
        case transportUrl
        case manifest
    }

    init(
        id: String,
        name: String,
        version: String,
        manifestURL: String,
        description: String?,
        catalogs: [String],
        resources: [String],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.manifestURL = manifestURL
        self.description = description
        self.catalogs = catalogs
        self.resources = resources
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decode(String.self, forKey: .name)) ?? "Addon"
        version = (try? container.decode(String.self, forKey: .version)) ?? "1.0.0"
        description = try? container.decode(String.self, forKey: .description)
        let rawManifestURL = try? container.decode(String.self, forKey: .manifestURL)
        let url = try? container.decode(String.self, forKey: .url)
        let transportURL = try? container.decode(String.self, forKey: .transportUrl)
        manifestURL = Self.normalizedManifestURL(rawManifestURL ?? url ?? transportURL ?? "")

        if let androidManifest = try? container.decode(AddonManifest.self, forKey: .manifest) {
            catalogs = androidManifest.catalogs?.compactMap { $0.name ?? $0.id ?? $0.type } ?? []
            resources = androidManifest.resources?.map(\.displayName) ?? []
        } else {
            catalogs = (try? container.decode([String].self, forKey: .catalogs)) ?? []
            resources = (try? container.decode([String].self, forKey: .resources)) ?? []
        }
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ??
            (try? container.decode(Bool.self, forKey: .enabled)) ??
            true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(manifestURL, forKey: .manifestURL)
        try container.encode(description, forKey: .description)
        try container.encode(catalogs, forKey: .catalogs)
        try container.encode(resources, forKey: .resources)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(manifestBaseURL(manifestURL), forKey: .url)
        try container.encode(manifestBaseURL(manifestURL), forKey: .transportUrl)
    }

    private static func normalizedManifestURL(_ rawURL: String) -> String {
        guard !rawURL.isEmpty else { return "" }
        if rawURL.hasSuffix("/manifest.json") { return rawURL }
        return rawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/manifest.json"
    }

    private func manifestBaseURL(_ rawURL: String) -> String {
        rawURL.replacingOccurrences(of: "/manifest.json", with: "")
    }
}

private struct AddonManifest: Codable {
    let id: String?
    let name: String
    let version: String?
    let description: String?
    let catalogs: [AddonCatalog]?
    let resources: [AddonResourceValue]?
}

private struct AddonCatalog: Codable {
    let type: String?
    let id: String?
    let name: String?
}

private enum AddonResourceValue: Codable {
    case string(String)
    case object(name: String?)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        let object = try container.decode(ResourceObject.self)
        self = .object(name: object.name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let name):
            try container.encode(ResourceObject(name: name))
        }
    }

    var displayName: String {
        switch self {
        case .string(let value):
            return value
        case .object(let name):
            return name ?? "resource"
        }
    }

    private struct ResourceObject: Codable {
        let name: String?
    }
}

@MainActor
final class AddonService: ObservableObject {
    @Published private(set) var addons: [InstalledAddon] = []
    @Published var installURL = ""
    @Published var errorMessage: String?

    private let cloud: CloudSyncService
    private let storageKey = "arvio.ios.installedAddons"
    private var activeProfileId: String?

    init(cloud: CloudSyncService) {
        self.cloud = cloud
        loadLocal()
    }

    func loadFromCloud() {
        let profileAddons = activeProfileId.flatMap { cloud.payload.addonsByProfile?[$0] }
        let mergedByProfile = cloud.payload.addonsByProfile?.values.flatMap { $0 } ?? []
        let resolved = profileAddons ?? (!mergedByProfile.isEmpty ? mergedByProfile : cloud.payload.addons)
        let valid = deduplicate(resolved).filter { !$0.manifestURL.isEmpty }
        if !valid.isEmpty {
            addons = valid
            saveLocal()
        }
    }

    func setActiveProfileId(_ profileId: String?) {
        activeProfileId = profileId
        loadFromCloud()
    }

    func install() async {
        let trimmed = installURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let addon = try await fetchAddon(from: trimmed)
            if let index = addons.firstIndex(where: { $0.id == addon.id }) {
                addons[index] = addon
            } else {
                addons.append(addon)
            }
            installURL = ""
            errorMessage = nil
            saveLocal()
            await cloud.save(addons: addons, profileId: activeProfileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ addon: InstalledAddon) async {
        addons.removeAll { $0.id == addon.id }
        saveLocal()
        await cloud.save(addons: addons, profileId: activeProfileId)
    }

    func toggleEnabled(_ addon: InstalledAddon) async {
        guard let index = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        addons[index].isEnabled.toggle()
        saveLocal()
        await cloud.save(addons: addons, profileId: activeProfileId)
    }

    private func fetchAddon(from rawURL: String) async throws -> InstalledAddon {
        let manifestURL = normalizedManifestURL(rawURL)
        guard let url = URL(string: manifestURL) else {
            throw ArvioError.invalidURL(rawURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ArvioError.requestFailed("Addon manifest failed to load")
        }
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
        let catalogs = manifest.catalogs?.compactMap { catalog in
            catalog.name ?? catalog.id ?? catalog.type
        } ?? []
        let resources = manifest.resources?.map(\.displayName) ?? []
        return InstalledAddon(
            id: manifest.id ?? manifestURL,
            name: manifest.name,
            version: manifest.version ?? "1.0.0",
            manifestURL: manifestURL,
            description: manifest.description,
            catalogs: catalogs,
            resources: resources
        )
    }

    private func normalizedManifestURL(_ rawURL: String) -> String {
        if rawURL.hasSuffix("/manifest.json") { return rawURL }
        return rawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/manifest.json"
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([InstalledAddon].self, from: data) else {
            return
        }
        addons = saved
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func deduplicate(_ values: [InstalledAddon]) -> [InstalledAddon] {
        var seen = Set<String>()
        return values.filter { addon in
            let key = addon.id + "|" + addon.manifestURL
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
