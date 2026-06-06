import SwiftUI
import UIKit

private enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts
    case profiles
    case liveTV
    case sources
    case playback
    case subtitles
    case appearance
    case network
    case catalogs
    case sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .profiles: return "Profiles"
        case .liveTV: return "Live TV"
        case .sources: return "Sources"
        case .playback: return "Playback"
        case .subtitles: return "Subtitles"
        case .appearance: return "Appearance"
        case .network: return "Network"
        case .catalogs: return "Catalogs"
        case .sync: return "Sync"
        }
    }

    var iconName: String {
        switch self {
        case .accounts: return "person.crop.circle.fill"
        case .profiles: return "person.2.fill"
        case .liveTV: return "dot.radiowaves.left.and.right"
        case .sources: return "square.stack.3d.up.fill"
        case .playback: return "play.rectangle.fill"
        case .subtitles: return "captions.bubble.fill"
        case .appearance: return "paintpalette.fill"
        case .network: return "network"
        case .catalogs: return "rectangle.grid.2x2.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .accounts: return "Cloud, Trakt, privacy"
        case .profiles: return "Profile identity and PIN"
        case .liveTV: return "IPTV, EPG, Stalker"
        case .sources: return "Addons, plugins, servers"
        case .playback: return "Autoplay, quality, torrents"
        case .subtitles: return "Languages, style, AI"
        case .appearance: return "Cards and visual chrome"
        case .network: return "DNS and User-Agent"
        case .catalogs: return "Home rows and lists"
        case .sync: return "Cloud state summary"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSettingsSection: SettingsSection = .accounts
    @State private var email = ""
    @State private var password = ""
    @State private var newCatalogTitle = ""
    @State private var newCatalogUrl = ""
    @State private var newCatalogType = CatalogSourceType.trakt
    @State private var addonInstallURL = ""
    @State private var homeServerUrl = ""
    @State private var homeServerUsername = ""
    @State private var homeServerSecret = ""
    @State private var homeServerDisplayName = ""
    @State private var homeServerStatus = ""
    @State private var newQualityFilterName = ""
    @State private var newQualityFilterRegex = ""
    @State private var qualityFilterError = ""
    @State private var catalogSearchQuery = ""
    @State private var iptvPlaylistName = ""
    @State private var iptvM3uUrl = ""
    @State private var iptvEpgUrl = ""
    @State private var iptvStalkerPortalUrl = ""
    @State private var iptvStalkerMacAddress = ""
    @State private var iptvStatus = ""
    @State private var iptvDiagnostics: [IptvProviderDiagnostic] = []

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 860
            if wide {
                HStack(spacing: 0) {
                    settingsSectionSidebar
                        .frame(width: 244)
                    ScrollView {
                        selectedSettingsContent
                            .padding(28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        settingsSectionStrip
                        selectedSettingsContent
                    }
                    .padding(20)
                }
            }
        }
        .task {
            syncIptvFormFromState()
        }
    }

    private var settingsSectionSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(ArvioTheme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 24)

            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSectionButton(section, compact: false)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.22))
        .overlay(Rectangle().fill(ArvioTheme.border).frame(width: 1), alignment: .trailing)
    }

    private var settingsSectionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSectionButton(section, compact: true)
                }
            }
        }
    }

    private func settingsSectionButton(_ section: SettingsSection, compact: Bool) -> some View {
        Button {
            selectedSettingsSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.iconName)
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: compact ? 13 : 15, weight: .bold))
                        .lineLimit(1)
                    if !compact {
                        Text(section.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedSettingsSection == section ? ArvioTheme.textSecondary : ArvioTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                if !compact { Spacer() }
            }
            .foregroundStyle(selectedSettingsSection == section ? ArvioTheme.textPrimary : ArvioTheme.textSecondary)
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 10 : 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedSettingsSection == section ? ArvioTheme.gold.opacity(0.16) : Color.white.opacity(compact ? 0.06 : 0.0)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedSettingsSection == section ? ArvioTheme.gold.opacity(0.85) : ArvioTheme.border.opacity(compact ? 1 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedSettingsSection {
            case .accounts:
                cloudPanel
                traktPanel
            case .profiles:
                profilePanel
            case .liveTV:
                iptvPanel
            case .sources:
                homeServerPanel
                stremioPanel
                pluginsPanel
            case .playback:
                playbackPanel
            case .subtitles:
                subtitlePanel
                aiSubtitlePanel
            case .appearance:
                interfacePanel
            case .network:
                networkPanel
            case .catalogs:
                catalogPanel
            case .sync:
                syncSummaryPanel
            }
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

                    Button("Use Device Code") {
                        Task { await appState.auth.beginCloudDeviceLink() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let code = appState.auth.cloudDeviceAuthSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text(code.userCode)
                        .font(.system(size: 30, weight: .black, design: .monospaced))
                        .foregroundStyle(ArvioTheme.gold)
                    Text(code.verificationURL)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .lineLimit(1)
                    HStack {
                        Button("Open Auth Page") {
                            openExternalURL(code.verificationURL)
                        }
                        .buttonStyle(.bordered)

                        Button("I approved it") {
                            Task {
                                await appState.auth.pollCloudDeviceLink()
                                await appState.reloadCloudState()
                                await appState.watchHistory.load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
            }

            if let message = appState.auth.cloudDeviceAuthMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArvioTheme.textSecondary)
            }

            Button("Privacy & Account Deletion") {
                openExternalURL("https://auth.arvio.tv/delete")
            }
            .buttonStyle(.bordered)

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

    private var iptvPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                panelHeader("Live TV / IPTV", "Manage M3U, Xtream, EPG, Stalker, provider checks, and cloud-synced TV preferences.")
                Spacer()
                Button(appState.iptv.isLoading ? "Loading" : "Refresh") {
                    Task {
                        await appState.iptv.reload()
                        syncIptvFormFromState()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .disabled(appState.iptv.isLoading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                iptvMetric(title: "Channels", value: "\(appState.iptv.channels.count)")
                iptvMetric(title: "Groups", value: "\(max(appState.iptv.groups.count - 2, 0))")
                iptvMetric(title: "Playlists", value: "\(appState.iptv.editablePlaylists().count)")
                iptvMetric(title: "Favorites", value: "\(appState.iptv.state.favoriteChannels.count)")
            }

            if appState.iptv.isLoading || !appState.iptv.progressMessage.isEmpty {
                Text(appState.iptv.progressMessage.isEmpty ? "Loading providers..." : appState.iptv.progressMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArvioTheme.gold)
            }

            if let error = appState.iptv.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if !iptvStatus.isEmpty {
                Text(iptvStatus)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iptvStatus.localizedCaseInsensitiveContains("failed") ? Color.red.opacity(0.9) : ArvioTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsValueLabel(title: "Provider order", value: "First enabled provider is preferred for VOD/source matching.")
                    Spacer()
                    Button("Sync from Cloud") {
                        appState.iptv.loadFromCloud()
                        syncIptvFormFromState(force: true)
                    }
                    .buttonStyle(.bordered)
                }

                let playlists = appState.iptv.editablePlaylists()
                if playlists.isEmpty {
                    Text("No M3U or Xtream playlists are configured for this profile.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                } else {
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { pair in
                        let index = pair.offset
                        let playlist = pair.element
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(playlist.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(ArvioTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(playlist.enabled ? "Enabled" : "Disabled")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(playlist.enabled ? ArvioTheme.gold : ArvioTheme.textTertiary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                                    }
                                    Text(playlistSubtitle(playlist))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(ArvioTheme.textTertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        playlistActions(playlist: playlist, index: index, count: playlists.count)
                                    }
                                    VStack(alignment: .trailing, spacing: 8) {
                                        playlistActions(playlist: playlist, index: index, count: playlists.count)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(playlist.enabled ? ArvioTheme.gold.opacity(0.1) : Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(playlist.enabled ? ArvioTheme.gold.opacity(0.6) : ArvioTheme.border, lineWidth: 1))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                SettingsValueLabel(title: "Primary provider", value: "Use the same URL shapes as Android: M3U, Xtream M3U, or provider-generated playlist links.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    TextField("Playlist name", text: $iptvPlaylistName)
                        .settingsField()
                    TextField("M3U / Xtream URL", text: $iptvM3uUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .settingsField()
                    TextField("EPG/XMLTV URL", text: $iptvEpgUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .settingsField()
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        primaryIptvActions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        primaryIptvActions
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                SettingsValueLabel(title: "Stalker portal", value: "Portal URL and MAC address are stored in the same profile state as Live TV.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    TextField("Portal URL", text: $iptvStalkerPortalUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .settingsField()
                    TextField("MAC address", text: $iptvStalkerMacAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsField()
                }
                Button("Save Stalker") {
                    Task { await saveIptvStalker() }
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsValueLabel(title: "Provider diagnostics", value: "Tests Xtream endpoints, M3U/EPG URLs, and Stalker login before you open Live TV.")
                    Spacer()
                    Button("Run Check") {
                        Task { await runIptvDiagnostics() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                }

                if iptvDiagnostics.isEmpty {
                    Text("No provider check has been run in this session.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArvioTheme.textTertiary)
                } else {
                    ForEach(iptvDiagnostics) { result in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(result.isSuccess ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(result.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                                .frame(width: 132, alignment: .leading)
                            Text(result.status)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(result.isSuccess ? Color.green.opacity(0.95) : Color.orange.opacity(0.95))
                                .frame(width: 84, alignment: .leading)
                            Text(result.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ArvioTheme.textSecondary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
        }
        .settingsPanel()
    }

    private var stremioPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                panelHeader("Stremio Addons", "Install Stremio-compatible manifests and sync them through ARVIO cloud.")
                Spacer()
                Text("\(appState.addons.addons.count) installed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ArvioTheme.textTertiary)
            }

            HStack(spacing: 10) {
                TextField("https://example.com/manifest.json", text: $addonInstallURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .settingsField()
                Button("Install") {
                    appState.addons.installURL = addonInstallURL
                    Task {
                        await appState.addons.install()
                        await appState.catalogs.syncAddonCatalogs()
                        addonInstallURL = appState.addons.installURL
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
            }

            if let error = appState.addons.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if appState.addons.addons.isEmpty {
                Text("No Stremio addons installed for this profile.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            } else {
                ForEach(appState.addons.addons) { addon in
                    AddonRow(addon: addon) {
                        Task {
                            await appState.addons.toggleEnabled(addon)
                            await appState.catalogs.syncAddonCatalogs()
                        }
                    } onRemove: {
                        Task {
                            await appState.addons.remove(addon)
                            await appState.catalogs.syncAddonCatalogs()
                        }
                    }
                }
            }
        }
        .settingsPanel()
    }

    private var pluginsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                panelHeader("Plugins & Extensions", "Manage Android-style plugin repositories and scraper metadata.")
                Spacer()
                SettingsToggle("Enabled", isOn: Binding(
                    get: { appState.plugins.pluginsEnabled },
                    set: { appState.plugins.setPluginsEnabled($0) }
                ))
                .frame(width: 150)
            }

            HStack(spacing: 10) {
                TextField("Repository URL or short code", text: pluginRepositoryInputBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .settingsField()
                Button(appState.plugins.isLoading ? "Working" : "Add Repository") {
                    Task { await appState.plugins.addRepository() }
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .disabled(appState.plugins.isLoading)
            }

            SettingsToggle("Group source results by repository", isOn: Binding(
                get: { appState.plugins.groupStreamsByRepository },
                set: { appState.plugins.setGroupStreamsByRepository($0) }
            ))

            if let success = appState.plugins.successMessage {
                Text(success)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.green.opacity(0.9))
            }
            if let error = appState.plugins.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if appState.plugins.repositories.isEmpty {
                Text("No plugin repositories installed.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            } else {
                ForEach(appState.plugins.repositories) { repository in
                    pluginRepositoryRow(repository)
                }
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
            Stepper(value: profileBinding(\.trailerDelaySeconds), in: 0...10) {
                SettingsValueLabel(title: "Trailer delay", value: "\(appState.settings.profileSettings.trailerDelaySeconds)s")
            }
            SettingsPicker(title: "Minimum auto-play quality", selection: profileBinding(\.autoPlayMinQuality), values: ["Any", "720p", "1080p", "4K"])
            SettingsPicker(title: "Quality filter", selection: qualityFilterPresetBinding, values: ["Off", "1080p+", "1080p only", "720p+", "Custom"])
            if qualityFilterPresetBinding.wrappedValue == "Custom" {
                TextField("Custom exclude regex", text: qualityFilterCustomRegexBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsField()
            }
            qualityFilterManagement
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
            SettingsPicker(title: "Subtitle offset", selection: profileBinding(\.subtitleOffset), values: ["Bottom", "Medium", "High"])
            SettingsToggle("Stylized subtitles", isOn: profileBinding(\.subtitleStylized))
            SettingsToggle("Filter subtitles by language", isOn: profileBinding(\.filterSubtitlesByLanguage))
            SettingsToggle("Remove hearing-impaired subtitles", isOn: globalBinding(\.subtitleRemoveHearingImpaired))
        }
        .settingsPanel()
    }

    private var interfacePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Appearance", "Home, catalog, profile, and visual preferences.")
            SettingsPicker(title: "Card layout", selection: profileBinding(\.cardLayoutMode), values: ["Landscape", "Portrait", "Compact"])
            SettingsPicker(title: "Content language", selection: profileBinding(\.contentLanguage), values: ["en-US", "nl-NL", "es-ES", "fr-FR", "de-DE"])
            SettingsPicker(title: "Clock format", selection: profileBinding(\.clockFormat), values: ["24h", "12h"])
            SettingsPicker(title: "Accent color", selection: profileBinding(\.accentColor), values: ["White", "Gold", "Cyan", "Green", "Pink"])
            SettingsToggle("Show budget", isOn: profileBinding(\.showBudget))
            SettingsToggle("OLED black background", isOn: profileBinding(\.oledBlackBackground))
            SettingsToggle("Smooth scrolling", isOn: profileBinding(\.smoothScrolling))
            SettingsToggle("Blur spoilers", isOn: profileBinding(\.spoilerBlurEnabled))
            SettingsToggle("Skip profile selection", isOn: globalBinding(\.skipProfileSelection))
        }
        .settingsPanel()
    }

    private var networkPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Network", "DNS, User-Agent, and loading diagnostics.")
            SettingsPicker(title: "DNS provider", selection: profileBinding(\.dnsProvider), values: ["system", "cloudflare", "google", "adguard"])
            TextField("Custom User-Agent", text: profileBinding(\.customUserAgent))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .settingsField()
            SettingsToggle("Show loading stats", isOn: profileBinding(\.showLoadingStats))
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Discover public catalogs")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                HStack(spacing: 10) {
                    TextField("Search Trakt and MDBList", text: $catalogSearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsField()
                        .onSubmit {
                            Task { await appState.catalogs.searchCatalogLists(catalogSearchQuery) }
                        }
                    Button(appState.catalogs.isDiscovering ? "Searching" : "Search") {
                        Task { await appState.catalogs.searchCatalogLists(catalogSearchQuery) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                    .disabled(appState.catalogs.isDiscovering)
                }

                if !appState.catalogs.discoveryResults.isEmpty {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.catalogs.discoveryResults) { result in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ArvioTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(catalogDiscoverySubtitle(result))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(ArvioTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Add") {
                                    Task { await appState.catalogs.addDiscoveredCatalog(result) }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035)))
                        }
                    }
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
            SettingsRow(title: "Stremio addons", value: "\(appState.addons.addons.count) installed")
            SettingsRow(title: "Plugin scrapers", value: "\(appState.plugins.enabledScrapers.count)/\(appState.plugins.scrapers.count) enabled")
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

    private func iptvMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ArvioTheme.textTertiary)
            Text(value)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(ArvioTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func playlistActions(playlist: IptvPlaylistEntry, index: Int, count: Int) -> some View {
        Button(playlist.enabled ? "Disable" : "Enable") {
            Task { await appState.iptv.togglePlaylist(playlist) }
        }
        .buttonStyle(.bordered)

        Button("Up") {
            Task { await appState.iptv.movePlaylist(playlist, direction: -1) }
        }
        .buttonStyle(.bordered)
        .disabled(index == 0)

        Button("Down") {
            Task { await appState.iptv.movePlaylist(playlist, direction: 1) }
        }
        .buttonStyle(.bordered)
        .disabled(index >= count - 1)

        Button("Remove", role: .destructive) {
            Task { await appState.iptv.removePlaylist(playlist) }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var primaryIptvActions: some View {
        Button("Save and Load") {
            Task { await saveIptvPrimary(replaceExisting: true) }
        }
        .buttonStyle(.borderedProminent)
        .tint(ArvioTheme.gold)
        .disabled(iptvM3uUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button("Add as Provider") {
            Task { await saveIptvPrimary(replaceExisting: false) }
        }
        .buttonStyle(.bordered)
        .disabled(iptvM3uUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button("Run Check") {
            Task { await runIptvDiagnostics() }
        }
        .buttonStyle(.bordered)
    }

    private var qualityFilterManagement: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SettingsValueLabel(title: "Quality filters", value: "\(currentQualityFilters().filter(\.enabled).count)/\(currentQualityFilters().count) active")
                Spacer()
            }

            Text(qualityFilterHelpText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ArvioTheme.textTertiary)

            if currentQualityFilters().isEmpty {
                Text("No custom filters. Presets can still be selected above.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ArvioTheme.textTertiary)
            } else {
                ForEach(currentQualityFilters()) { filter in
                    qualityFilterRow(filter)
                }
            }

            HStack(spacing: 10) {
                TextField("Device/filter name", text: $newQualityFilterName)
                    .settingsField()
                TextField("Exclude regex", text: $newQualityFilterRegex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsField()
                Button("Add") {
                    addQualityFilter()
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .disabled(newQualityFilterRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !qualityFilterError.isEmpty {
                Text(qualityFilterError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private func qualityFilterRow(_ filter: QualityFilterConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { currentQualityFilters().first(where: { $0.id == filter.id })?.enabled ?? filter.enabled },
                    set: { value in updateQualityFilter(filter.id) { $0.enabled = value } }
                ))
                .labelsHidden()
                .tint(ArvioTheme.gold)

                TextField("Name", text: Binding(
                    get: { currentQualityFilters().first(where: { $0.id == filter.id })?.deviceName ?? filter.deviceName },
                    set: { value in updateQualityFilter(filter.id) { $0.deviceName = value } }
                ))
                .settingsField()

                Button("Delete", role: .destructive) {
                    removeQualityFilter(filter.id)
                }
                .buttonStyle(.bordered)
            }

            TextField("Regex", text: Binding(
                get: { currentQualityFilters().first(where: { $0.id == filter.id })?.regexPattern ?? filter.regexPattern },
                set: { value in updateQualityFilter(filter.id) { $0.regexPattern = value } }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .settingsField()

            if !isValidRegex(filter.regexPattern) {
                Text("Invalid regex. This filter will not be saved until it compiles.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(filter.enabled ? ArvioTheme.gold.opacity(0.1) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(filter.enabled ? ArvioTheme.gold.opacity(0.55) : ArvioTheme.border, lineWidth: 1))
    }

    private func pluginRepositoryRow(_ repository: PluginRepositoryRecord) -> some View {
        let repositoryScrapers = appState.plugins.scrapers.filter { $0.repositoryId == repository.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(repository.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                            .lineLimit(1)
                        Text(repository.type.displayName)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(repository.type == .externalDEX ? Color.orange.opacity(0.95) : ArvioTheme.gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                    }
                    Text(repository.description?.isEmpty == false ? repository.description! : repository.url)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .lineLimit(2)
                    Text("\(repositoryScrapers.count) scraper(s) - \(repositoryScrapers.filter(\.enabled).count) enabled")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ArvioTheme.textTertiary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await appState.plugins.refreshRepository(repository) }
                }
                .buttonStyle(.bordered)
                Button("Enable All") {
                    appState.plugins.toggleAllScrapers(in: repository, enabled: true)
                }
                .buttonStyle(.bordered)
                Button("Disable All") {
                    appState.plugins.toggleAllScrapers(in: repository, enabled: false)
                }
                .buttonStyle(.bordered)
                Button("Remove", role: .destructive) {
                    appState.plugins.removeRepository(repository)
                }
                .buttonStyle(.bordered)
            }

            if repository.type == .externalDEX {
                Text("Android DEX extensions are shown for account/configuration parity. They cannot execute inside the iOS app.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }

            if repositoryScrapers.isEmpty {
                Text("No scrapers were found in this repository.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ArvioTheme.textTertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    ForEach(repositoryScrapers) { scraper in
                        pluginScraperRow(scraper)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private func pluginScraperRow(_ scraper: PluginScraperRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(scraper.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.plugins.scrapers.first(where: { $0.id == scraper.id })?.enabled ?? scraper.enabled },
                    set: { _ in appState.plugins.toggleScraper(scraper) }
                ))
                .labelsHidden()
                .tint(ArvioTheme.gold)
                .disabled(!scraper.manifestEnabled)
            }
            if !scraper.description.isEmpty {
                Text(scraper.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(scraper.version)
                Text(scraper.supportedTypes.prefix(3).joined(separator: ", "))
                if !scraper.supportsIOSExecution {
                    Text("Android runtime")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ArvioTheme.textTertiary)
            Button(appState.plugins.isTesting ? "Testing" : "Test") {
                Task { await appState.plugins.testScraper(scraper) }
            }
            .buttonStyle(.bordered)
            .disabled(appState.plugins.isTesting)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(scraper.enabled ? ArvioTheme.gold.opacity(0.11) : Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(scraper.enabled ? ArvioTheme.gold.opacity(0.65) : ArvioTheme.border, lineWidth: 1))
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<CloudProfileSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.settings.profileSettings[keyPath: keyPath] },
            set: { value in
                Task { await appState.settings.updateProfile { $0[keyPath: keyPath] = value } }
            }
        )
    }

    private var pluginRepositoryInputBinding: Binding<String> {
        Binding(
            get: { appState.plugins.repositoryInput },
            set: { appState.plugins.repositoryInput = $0 }
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

    private func saveIptvPrimary(replaceExisting: Bool) async {
        iptvStatus = "Saving provider..."
        let name = iptvPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let m3u = iptvM3uUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let epg = iptvEpgUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m3u.isEmpty else {
            iptvStatus = "Enter an M3U or Xtream URL first."
            return
        }

        if replaceExisting {
            await appState.iptv.saveConfig(m3uUrl: m3u, epgUrl: epg)
        } else {
            await appState.iptv.addPlaylist(name: name, m3uUrl: m3u, epgUrl: epg)
        }

        if !iptvStalkerPortalUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !iptvStalkerMacAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appState.iptv.saveStalkerConfig(
                portalUrl: iptvStalkerPortalUrl,
                macAddress: iptvStalkerMacAddress
            )
        }

        syncIptvFormFromState(force: true)
        iptvStatus = replaceExisting ? "Primary provider saved and loaded." : "Provider added and loaded."
    }

    private func saveIptvStalker() async {
        iptvStatus = "Saving Stalker portal..."
        await appState.iptv.saveStalkerConfig(
            portalUrl: iptvStalkerPortalUrl,
            macAddress: iptvStalkerMacAddress
        )
        syncIptvFormFromState(force: true)
        iptvStatus = "Stalker portal saved."
    }

    private func runIptvDiagnostics() async {
        iptvStatus = "Checking provider..."
        iptvDiagnostics = await appState.iptv.runProviderDiagnostics(
            m3uUrl: iptvM3uUrl,
            epgUrl: iptvEpgUrl,
            stalkerPortalUrl: iptvStalkerPortalUrl,
            stalkerMacAddress: iptvStalkerMacAddress
        )
        let failures = iptvDiagnostics.filter { !$0.isSuccess }
        iptvStatus = failures.isEmpty ? "Provider check passed." : "Provider check finished with \(failures.count) warning(s)."
    }

    private func syncIptvFormFromState(force: Bool = false) {
        let playlists = appState.iptv.editablePlaylists()
        if force || iptvPlaylistName.isEmpty {
            iptvPlaylistName = playlists.first?.name ?? "Playlist \(max(playlists.count + 1, 1))"
        }
        if force || iptvM3uUrl.isEmpty {
            iptvM3uUrl = playlists.first?.m3uUrl ?? appState.iptv.state.m3uUrl
        }
        if force || iptvEpgUrl.isEmpty {
            iptvEpgUrl = playlists.first?.epgUrl ?? appState.iptv.state.epgUrl
        }
        if force || iptvStalkerPortalUrl.isEmpty {
            iptvStalkerPortalUrl = appState.iptv.state.stalkerPortalUrl
        }
        if force || iptvStalkerMacAddress.isEmpty {
            iptvStalkerMacAddress = appState.iptv.state.stalkerMacAddress
        }
    }

    private func playlistSubtitle(_ playlist: IptvPlaylistEntry) -> String {
        let values = [
            playlist.m3uUrl,
            playlist.epgUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "EPG: \(playlist.epgUrl)"
        ]
        return values.compactMap { $0 }.joined(separator: " - ")
    }

    private func openExternalURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        UIApplication.shared.open(url)
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

    private func catalogDiscoverySubtitle(_ result: CatalogDiscoveryResult) -> String {
        [
            result.sourceType.rawValue,
            result.creatorName,
            result.itemCount.map { "\($0) items" },
            result.likes.map { "\($0) likes" },
            result.description
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private var qualityFilterPresetBinding: Binding<String> {
        Binding(
            get: { detectQualityFilterPreset(from: appState.settings.profileSettings.qualityFiltersJson) },
            set: { preset in
                if preset != "Custom" && preset != "Off" && detectQualityFilterPreset(from: appState.settings.profileSettings.qualityFiltersJson) == "Custom" {
                    qualityFilterError = "Custom filters detected. Edit or delete them before selecting a preset."
                    return
                }
                qualityFilterError = ""
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
                let trimmed = regex.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty || isValidRegex(trimmed) else {
                    qualityFilterError = "Invalid regular expression."
                    return
                }
                qualityFilterError = ""
                Task {
                    await appState.settings.updateProfile {
                        $0.qualityFiltersJson = makeQualityFiltersJson(preset: "Custom", customRegex: trimmed)
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

    private func addQualityFilter() {
        let regex = newQualityFilterRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !regex.isEmpty else { return }
        guard isValidRegex(regex) else {
            qualityFilterError = "Invalid regular expression."
            return
        }
        var filters = currentQualityFilters()
        filters.append(QualityFilterConfig(
            id: "ios_quality_\(UUID().uuidString)",
            deviceName: newQualityFilterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UIDevice.current.name : newQualityFilterName,
            regexPattern: regex,
            enabled: true,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        ))
        newQualityFilterName = ""
        newQualityFilterRegex = ""
        qualityFilterError = ""
        Task { await saveQualityFilters(filters) }
    }

    private func updateQualityFilter(_ id: String, mutate: @escaping (inout QualityFilterConfig) -> Void) {
        var filters = currentQualityFilters()
        guard let index = filters.firstIndex(where: { $0.id == id }) else { return }
        mutate(&filters[index])
        let regex = filters[index].regexPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard regex.isEmpty || isValidRegex(regex) else {
            qualityFilterError = "Invalid regular expression."
            return
        }
        qualityFilterError = ""
        Task { await saveQualityFilters(filters) }
    }

    private func removeQualityFilter(_ id: String) {
        let filters = currentQualityFilters().filter { $0.id != id }
        qualityFilterError = ""
        Task { await saveQualityFilters(filters) }
    }

    private func saveQualityFilters(_ filters: [QualityFilterConfig]) async {
        let cleaned = filters
            .map { filter in
                QualityFilterConfig(
                    id: filter.id,
                    deviceName: filter.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UIDevice.current.name : filter.deviceName,
                    regexPattern: filter.regexPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                    enabled: filter.enabled,
                    createdAt: filter.createdAt
                )
            }
            .filter { !$0.regexPattern.isEmpty }
        let json: String
        if cleaned.isEmpty {
            json = ""
        } else if let data = try? JSONEncoder().encode(cleaned) {
            json = String(decoding: data, as: UTF8.self)
        } else {
            json = appState.settings.profileSettings.qualityFiltersJson
        }
        await appState.settings.updateProfile {
            $0.qualityFiltersJson = json
        }
    }

    private var qualityFilterHelpText: String {
        "Matching sources are excluded before playback, using the same regex rules as Android presets."
    }

    private func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil
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
