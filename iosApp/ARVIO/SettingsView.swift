import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)

                cloudPanel
                traktPanel
                profilePanel
                playbackPanel
                subtitlePanel
                interfacePanel
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
            Button("Switch") {
                appState.profiles.isSwitcherVisible = true
            }
            .buttonStyle(.borderedProminent)
            .tint(ArvioTheme.gold)
        }
        .settingsPanel()
    }

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Playback", "Matches Android playback preferences saved in ARVIO cloud.")
            SettingsToggle("Auto-play next episode", isOn: profileBinding(\.autoPlayNext))
            SettingsToggle("Auto-play when one source exists", isOn: profileBinding(\.autoPlaySingleSource))
            SettingsPicker(title: "Minimum auto-play quality", selection: profileBinding(\.autoPlayMinQuality), values: ["Any", "720p", "1080p", "4K"])
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

    private var aiSubtitlePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("AI Subtitles", "The same cloud keys Android uses for AI subtitle generation.")
            SettingsToggle("Enable AI subtitles", isOn: globalBinding(\.subtitleAiEnabled))
            SettingsToggle("Auto-select AI subtitles", isOn: globalBinding(\.subtitleAiAutoSelect))
            SettingsPicker(title: "AI model", selection: globalBinding(\.subtitleAiModel), values: ["GROQ_LLAMA_70B", "OPENAI_GPT_4O_MINI", "OPENAI_GPT_4O"])
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
