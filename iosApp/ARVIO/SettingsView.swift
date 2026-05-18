import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var newCatalogTitle = ""
    @State private var newCatalogUrl = ""
    @State private var newCatalogType = CatalogSourceType.trakt
    @State private var homeServerUrl = ""
    @State private var homeServerUsername = ""
    @State private var homeServerSecret = ""
    @State private var homeServerDisplayName = ""
    @State private var homeServerStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)

                cloudPanel
                traktPanel
                profilePanel
                homeServerPanel
                playbackPanel
                subtitlePanel
                interfacePanel
                catalogPanel
                aiSubtitlePanel
                syncSummaryPanel
            }
            .padding(28)
        }
    }

    private var cloudPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud login")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Text(appState.auth.session?.email ?? "Use the same ARVIO account as Android.")
                        .font(.system(size: 14))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
                Spacer()
                if appState.auth.isAuthenticated {
                    Button("Sign out") { appState.auth.signOut() }
                        .buttonStyle(.bordered)
                }
            }

            if !appState.auth.isAuthenticated {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .settingsField()
                SecureField("Password", text: $password)
                    .settingsField()
                HStack {
                    Button("Sign in") {
                        Task {
                            await appState.auth.signIn(email: email, password: password)
                            await appState.reloadCloudState()
                            await appState.watchHistory.load()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)

                    Button("Create account") {
                        Task {
                            await appState.auth.signUp(email: email, password: password)
                            await appState.reloadCloudState()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = appState.auth.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .settingsPanel()
    }

    private var homeServerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                panelHeader("Home Server", "Connect Plex, Jellyfin, or Emby and use the same cloud format as Android.")
                Spacer()
                Button("Test") {
                    Task { await testHomeServerConnections() }
                }
                .buttonStyle(.bordered)
                .disabled(homeServerConnections.isEmpty)
                Button("Sync Libraries") {
                    Task { await appState.catalogs.syncHomeServerCatalogs() }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .disabled(homeServerConnections.isEmpty)
            }

            if homeServerConnections.isEmpty {
                Text("No personal server is connected for this profile.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            } else {
                ForEach(homeServerConnections) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connection.displayLabel)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                Text([connection.serverKind.rawValue, connection.userName, "\(connection.collections.filter(\.enabled).count) libraries"].filter { !$0.isEmpty }.joined(separator: " - "))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                            }
                            Spacer()
                            Button(connection.enabled ? "Disable" : "Enable") {
                                Task { await updateHomeServerConnection(connection) { $0.enabled.toggle() } }
                            }
                            .buttonStyle(.bordered)
                            Button("Remove", role: .destructive) {
                                Task { await removeHomeServerConnection(connection) }
                            }
                            .buttonStyle(.bordered)
                        }

                        if !connection.collections.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                                ForEach(connection.collections) { collection in
                                    Button {
                                        Task { await toggleHomeServerCollection(connection, collection) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(collection.name.isEmpty ? "Library" : collection.name)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .lineLimit(1)
                                                Text(collection.type.isEmpty ? "Collection" : collection.type)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(ArvioTheme.textTertiary)
                                            }
                                            Spacer()
                                            Text(collection.enabled ? "On" : "Off")
                                                .font(.system(size: 11, weight: .black))
                                                .foregroundStyle(collection.enabled ? ArvioTheme.gold : ArvioTheme.textTertiary)
                                        }
                                        .foregroundStyle(ArvioTheme.textPrimary)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(collection.enabled ? ArvioTheme.gold.opacity(0.12) : Color.white.opacity(0.04)))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(collection.enabled ? ArvioTheme.gold.opacity(0.7) : ArvioTheme.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Add server")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                TextField("Server URL, for example http://192.168.1.10:8096", text: $homeServerUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsField()
                HStack(spacing: 10) {
                    TextField("Username, optional for Plex token", text: $homeServerUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsField()
                    TextField("Display name", text: $homeServerDisplayName)
                        .settingsField()
                }
                SecureField("Password or Plex token", text: $homeServerSecret)
                    .settingsField()
                HStack {
                    Button("Connect") {
                        Task { await connectHomeServer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                    if !homeServerStatus.isEmpty {
                        Text(homeServerStatus)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(homeServerStatus.localizedCaseInsensitiveContains("failed") ? Color.red.opacity(0.9) : ArvioTheme.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
        }
        .settingsPanel()
    }

    private var traktPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trakt")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Text(appState.trakt.isConnected ? "Connected. Watchlist and playback sync are active." : "Link Trakt to mirror Android watchlist/history.")
                        .font(.system(size: 14))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
                Spacer()
                if appState.trakt.isConnected {
                    Button("Disconnect") { appState.trakt.disconnect() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Link") {
                        Task { await appState.trakt.beginDeviceLink() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                }
            }

            if let code = appState.trakt.deviceCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(code.userCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(ArvioTheme.gold)
                    Text(code.verificationURL)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                    Button("I approved it") {
                        Task {
                            await appState.trakt.pollForToken()
                            await appState.watchHistory.load()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = appState.trakt.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .settingsPanel()
    }

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProfileDot(profile: appState.profiles.activeProfile)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Text(appState.profiles.activeProfile?.name ?? "Default")
                        .font(.system(size: 14))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
                Spacer()
                Button("Avatar") {
                    Task { await appState.profiles.cycleActiveAvatarColor() }
                }
                .buttonStyle(.bordered)
                Button("Switch") {
                    appState.profiles.isSwitcherVisible = true
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
            }
            TextField("Profile name", text: activeProfileNameBinding)
                .settingsField()
            SecureField("Profile PIN, optional", text: activeProfilePinBinding)
                .keyboardType(.numberPad)
                .settingsField()
            SettingsToggle("Kids profile", isOn: activeProfileKidsBinding)
        }
        .settingsPanel()
    }

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Playback", "Matches Android playback preferences saved in ARVIO cloud.")
            SettingsToggle("Auto-play next episode", isOn: profileBinding(\.autoPlayNext))
            SettingsToggle("Auto-play when one source exists", isOn: profileBinding(\.autoPlaySingleSource))
            SettingsToggle("Auto-play trailers", isOn: profileBinding(\.trailerAutoPlay))
            SettingsToggle("Trailer sound", isOn: profileBinding(\.trailerSoundEnabled))
            SettingsPicker(title: "Minimum auto-play quality", selection: profileBinding(\.autoPlayMinQuality), values: ["Any", "720p", "1080p", "4K"])
            SettingsPicker(title: "Quality filter", selection: qualityFilterPresetBinding, values: ["Off", "1080p+", "1080p only", "720p+", "Custom"])
            if qualityFilterPresetBinding.wrappedValue == "Custom" {
                TextField("Custom exclude regex", text: qualityFilterCustomRegexBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsField()
            }
            TextField("TorrServer URL, for example http://127.0.0.1:8090", text: profileBinding(\.torrServerBaseUrl))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .settingsField()
            SettingsPicker(title: "Frame-rate matching", selection: profileBinding(\.frameRateMatchingMode), values: ["Off", "Seamless", "Non-seamless"])
            Stepper(value: profileBinding(\.volumeBoostDb), in: 0...15) {
                SettingsValueLabel(title: "Volume boost", value: "\(appState.settings.profileSettings.volumeBoostDb)dB")
            }
            SettingsToggle("Include specials", isOn: profileBinding(\.includeSpecials))
        }
        .settingsPanel()
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Subtitles", "Profile subtitle defaults synced with Android.")
            SettingsPicker(title: "Default subtitle", selection: profileBinding(\.defaultSubtitle), values: ["Off", "English", "Dutch", "Spanish", "French", "German", "Auto"])
            SettingsPicker(title: "Secondary subtitle", selection: profileBinding(\.secondarySubtitle), values: ["Off", "English", "Dutch", "Spanish", "French", "German"])
            SettingsPicker(title: "Audio language", selection: profileBinding(\.defaultAudioLanguage), values: ["Auto (Original)", "English", "Dutch", "Spanish", "French", "German", "Japanese"])
            SettingsPicker(title: "Subtitle size", selection: profileBinding(\.subtitleSize), values: ["Small", "Medium", "Large", "Extra Large"])
            SettingsPicker(title: "Subtitle color", selection: profileBinding(\.subtitleColor), values: ["White", "Yellow", "Cyan", "Green"])
            SettingsPicker(title: "Subtitle style", selection: profileBinding(\.subtitleStyle), values: ["Regular", "Bold", "Outline", "Shadow"])
            SettingsPicker(title: "Subtitle offset", selection: profileBinding(\.subtitleOffset), values: ["Low", "Medium", "High"])
            SettingsToggle("Stylized subtitles", isOn: profileBinding(\.subtitleStylized))
            SettingsToggle("Filter subtitles by language", isOn: profileBinding(\.filterSubtitlesByLanguage))
            SettingsToggle("Remove hearing-impaired subtitles", isOn: globalBinding(\.subtitleRemoveHearingImpaired))
        }
        .settingsPanel()
    }

    private var interfacePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Interface", "Home, catalog, profile, and network preferences.")
            SettingsPicker(title: "Card layout", selection: profileBinding(\.cardLayoutMode), values: ["Landscape", "Portrait", "Compact"])
            SettingsPicker(title: "Content language", selection: profileBinding(\.contentLanguage), values: ["en-US", "nl-NL", "es-ES", "fr-FR", "de-DE"])
            SettingsPicker(title: "Clock format", selection: profileBinding(\.clockFormat), values: ["24h", "12h"])
            SettingsPicker(title: "DNS provider", selection: profileBinding(\.dnsProvider), values: ["system", "cloudflare", "google", "quad9"])
            SettingsToggle("Show budget", isOn: profileBinding(\.showBudget))
            SettingsToggle("Blur spoilers", isOn: profileBinding(\.spoilerBlurEnabled))
            SettingsToggle("Skip profile selection", isOn: globalBinding(\.skipProfileSelection))
        }
        .settingsPanel()
    }

    private var catalogPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                panelHeader("Catalogs", "Manage home rows and row layout for this profile.")
                Spacer()
                Button("Refresh") {
                    Task { await appState.catalogs.reloadRows() }
                }
                .buttonStyle(.bordered)
                Button("Restore") {
                    Task { await appState.catalogs.restoreDefaultCatalogs() }
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Add custom catalog")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                HStack(spacing: 10) {
                    TextField("Title", text: $newCatalogTitle)
                        .settingsField()
                    TextField("Trakt/MDBList URL", text: $newCatalogUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsField()
                    Picker("Type", selection: $newCatalogType) {
                        Text("Trakt").tag(CatalogSourceType.trakt)
                        Text("MDBList").tag(CatalogSourceType.mdblist)
                    }
                    .pickerStyle(.menu)
                    .tint(ArvioTheme.gold)
                    Button("Add") {
                        Task {
                            await appState.catalogs.addCatalog(title: newCatalogTitle, sourceType: newCatalogType, sourceUrl: newCatalogUrl)
                            newCatalogTitle = ""
                            newCatalogUrl = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            if appState.catalogs.catalogs.isEmpty {
                Text("No catalog rows configured.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            } else {
                ForEach(Array(appState.catalogs.catalogs.enumerated()), id: \.offset) { index, catalog in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Catalog title", text: catalogTitleBinding(catalog))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                            Text([catalog.sourceType.rawValue, rowLayout(for: catalog)].joined(separator: " - "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ArvioTheme.textTertiary)
                        }
                        Spacer()
                        Picker("Layout", selection: catalogLayoutBinding(catalog)) {
                            Text("Landscape").tag("Landscape")
                            Text("Portrait").tag("Portrait")
                            Text("Compact").tag("Compact")
                        }
                        .pickerStyle(.menu)
                        .tint(ArvioTheme.gold)
                        Button("Up") {
                            Task { await appState.catalogs.moveCatalog(catalog, direction: -1) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(index == 0)
                        Button("Down") {
                            Task { await appState.catalogs.moveCatalog(catalog, direction: 1) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(index == appState.catalogs.catalogs.count - 1)
                        Button("Hide") {
                            Task { await appState.catalogs.hideCatalog(catalog) }
                        }
                        .buttonStyle(.bordered)
                        Button(configDeleteTitle(catalog), role: .destructive) {
                            Task { await appState.catalogs.deleteCatalog(catalog) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                }
            }
        }
        .settingsPanel()
    }

    private var aiSubtitlePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("AI Subtitles", "The same cloud keys Android uses for AI subtitle generation.")
            SettingsToggle("Enable AI subtitles", isOn: globalBinding(\.subtitleAiEnabled))
            SettingsToggle("Auto-select AI subtitles", isOn: globalBinding(\.subtitleAiAutoSelect))
            SettingsPicker(title: "AI model", selection: globalBinding(\.subtitleAiModel), values: ["GROQ_LLAMA_70B", "GEMINI_FLASH_25", "OPENAI_GPT_4O_MINI", "OPENAI_GPT_4O"])
            SecureField("API key", text: globalBinding(\.subtitleAiApiKey))
                .settingsField()
        }
        .settingsPanel()
    }

    private var syncSummaryPanel: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Cloud sync", value: appState.cloud.isSyncing ? "Syncing" : (appState.auth.isAuthenticated ? "Connected" : "Disconnected"))
            SettingsRow(title: "Addons", value: "\(appState.addons.addons.count) installed")
            SettingsRow(title: "Live TV", value: appState.iptv.channels.isEmpty ? "No channels loaded" : "\(appState.iptv.channels.count) channels")
            SettingsRow(title: "Playback", value: appState.selectedStream == nil ? "Ready" : "Playing")
        }
    }

    private func panelHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(ArvioTheme.textSecondary)
        }
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<CloudProfileSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.settings.profileSettings[keyPath: keyPath] },
            set: { value in
                Task { await appState.settings.updateProfile { $0[keyPath: keyPath] = value } }
            }
        )
    }

    private func globalBinding<Value>(_ keyPath: WritableKeyPath<GlobalCloudSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.settings.globalSettings[keyPath: keyPath] },
            set: { value in
                Task { await appState.settings.updateGlobal { $0[keyPath: keyPath] = value } }
            }
        )
    }

    private var homeServerConnections: [HomeServerConnection] {
        HomeServerService.parseConnections(appState.settings.profileSettings.homeServerConnectionJson)
    }

    private func connectHomeServer() async {
        homeServerStatus = "Connecting..."
        do {
            let connection = try await HomeServerService.connect(
                serverUrl: homeServerUrl,
                username: homeServerUsername,
                secret: homeServerSecret,
                displayName: homeServerDisplayName
            )
            var connections = homeServerConnections.filter { $0.id != connection.id }
            connections.append(connection)
            await saveHomeServerConnections(connections)
            await appState.catalogs.syncHomeServerCatalogs()
            homeServerUrl = ""
            homeServerUsername = ""
            homeServerSecret = ""
            homeServerDisplayName = ""
            homeServerStatus = "Connected \(connection.displayLabel)"
        } catch {
            homeServerStatus = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func testHomeServerConnections() async {
        homeServerStatus = "Testing..."
        let refreshed = await HomeServerService.testConnections(homeServerConnections)
        await saveHomeServerConnections(refreshed)
        await appState.catalogs.syncHomeServerCatalogs()
        homeServerStatus = refreshed.isEmpty ? "No usable server found" : "Tested \(refreshed.count) server(s)"
    }

    private func updateHomeServerConnection(_ connection: HomeServerConnection, mutate: (inout HomeServerConnection) -> Void) async {
        var connections = homeServerConnections
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        mutate(&connections[index])
        await saveHomeServerConnections(connections)
        await appState.catalogs.syncHomeServerCatalogs()
    }

    private func removeHomeServerConnection(_ connection: HomeServerConnection) async {
        let connections = homeServerConnections.filter { $0.id != connection.id }
        await saveHomeServerConnections(connections)
        await appState.catalogs.syncHomeServerCatalogs()
        homeServerStatus = "Removed \(connection.displayLabel)"
    }

    private func toggleHomeServerCollection(_ connection: HomeServerConnection, _ collection: HomeServerCollection) async {
        await updateHomeServerConnection(connection) { updated in
            guard let index = updated.collections.firstIndex(where: { $0.id == collection.id }) else { return }
            updated.collections[index].enabled.toggle()
        }
    }

    private func saveHomeServerConnections(_ connections: [HomeServerConnection]) async {
        await appState.settings.updateProfile {
            $0.homeServerConnectionJson = HomeServerService.encodeConnections(connections)
        }
    }

    private var activeProfileNameBinding: Binding<String> {
        Binding(
            get: { appState.profiles.activeProfile?.name ?? "" },
            set: { name in Task { await appState.profiles.renameActive(name) } }
        )
    }

    private var activeProfilePinBinding: Binding<String> {
        Binding(
            get: { appState.profiles.activeProfile?.pin ?? "" },
            set: { pin in Task { await appState.profiles.setActivePin(pin) } }
        )
    }

    private var activeProfileKidsBinding: Binding<Bool> {
        Binding(
            get: { appState.profiles.activeProfile?.isKidsProfile ?? false },
            set: { isKids in Task { await appState.profiles.setActiveKidsProfile(isKids) } }
        )
    }

    private func catalogLayoutBinding(_ catalog: CatalogConfig) -> Binding<String> {
        Binding(
            get: { rowLayout(for: catalog) },
            set: { layout in
                Task {
                    await appState.settings.updateProfile {
                        $0.catalogueRowLayoutModes[catalog.id] = layout
                    }
                }
            }
        )
    }

    private func catalogTitleBinding(_ catalog: CatalogConfig) -> Binding<String> {
        Binding(
            get: { appState.catalogs.catalogs.first(where: { $0.id == catalog.id })?.title ?? catalog.title },
            set: { title in Task { await appState.catalogs.renameCatalog(catalog, title: title) } }
        )
    }

    private func configDeleteTitle(_ catalog: CatalogConfig) -> String {
        catalog.isPreinstalled ? "Hide" : "Delete"
    }

    private func rowLayout(for catalog: CatalogConfig) -> String {
        appState.settings.profileSettings.catalogueRowLayoutModes[catalog.id]
            ?? (catalog.collectionTileShape == .poster ? "Portrait" : appState.settings.profileSettings.cardLayoutMode)
    }

    private var qualityFilterPresetBinding: Binding<String> {
        Binding(
            get: { detectQualityFilterPreset(from: appState.settings.profileSettings.qualityFiltersJson) },
            set: { preset in
                Task {
                    await appState.settings.updateProfile {
                        $0.qualityFiltersJson = makeQualityFiltersJson(preset: preset, customRegex: currentCustomQualityRegex())
                    }
                }
            }
        )
    }

    private var qualityFilterCustomRegexBinding: Binding<String> {
        Binding(
            get: { currentCustomQualityRegex() },
            set: { regex in
                Task {
                    await appState.settings.updateProfile {
                        $0.qualityFiltersJson = makeQualityFiltersJson(preset: "Custom", customRegex: regex)
                    }
                }
            }
        )
    }

    private func currentQualityFilters() -> [QualityFilterConfig] {
        guard let data = appState.settings.profileSettings.qualityFiltersJson.data(using: .utf8),
              let filters = try? JSONDecoder().decode([QualityFilterConfig].self, from: data) else {
            return []
        }
        return filters
    }

    private func currentCustomQualityRegex() -> String {
        currentQualityFilters().first(where: { $0.enabled && !$0.regexPattern.isEmpty })?.regexPattern ?? ""
    }

    private func detectQualityFilterPreset(from json: String) -> String {
        let filters: [QualityFilterConfig]
        if let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([QualityFilterConfig].self, from: data) {
            filters = decoded
        } else {
            filters = []
        }
        let enabled = filters.filter { $0.enabled && !$0.regexPattern.isEmpty }
        guard let first = enabled.first else { return "Off" }
        guard enabled.count == 1 else { return "Custom" }
        return qualityFilterPresets.first(where: { $0.value == first.regexPattern })?.key ?? "Custom"
    }

    private func makeQualityFiltersJson(preset: String, customRegex: String) -> String {
        let regex = qualityFilterPresets[preset] ?? (preset == "Custom" ? customRegex.trimmingCharacters(in: .whitespacesAndNewlines) : "")
        guard !regex.isEmpty else { return "" }
        let filter = QualityFilterConfig(
            id: preset == "Custom" ? "ios_custom_quality_filter" : "preset_quality_\(preset.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "+", with: "_plus"))",
            deviceName: preset == "Custom" ? UIDevice.current.name : "Preset: \(preset)",
            regexPattern: regex,
            enabled: true,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard let data = try? JSONEncoder().encode([filter]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private var qualityFilterPresets: [String: String] {
        [
            "1080p+": "(?:360|480|576|720)p|cam|hdcam|hdts|hdtc|telesync|telecine|ts|tc|screener|scr|sd",
            "1080p only": "(?:2160|4k|uhd)|(?:360|480|576|720)p|cam|hdcam|hdts|hdtc|telesync|telecine|ts|tc|screener|scr|sd",
            "720p+": "(?:360|480|576)p|cam|hdcam|hdts|hdtc|telesync|telecine|ts|tc|screener|scr|sd"
        ]
    }
}

private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ArvioTheme.textPrimary)
            .tint(ArvioTheme.gold)
    }
}

private struct SettingsPicker: View {
    let title: String
    @Binding var selection: String
    let values: [String]

    var body: some View {
        HStack {
            SettingsValueLabel(title: title, value: selection)
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(ArvioTheme.gold)
        }
    }
}

private struct SettingsValueLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ArvioTheme.textTertiary)
        }
    }
}

struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ArvioTheme.textSecondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}

extension View {
    func settingsPanel() -> some View {
        padding(18)
            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    func settingsField() -> some View {
        padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
            .foregroundStyle(ArvioTheme.textPrimary)
    }
}
