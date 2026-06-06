import AVKit
import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @State private var m3uUrl = ""
    @State private var epgUrl = ""
    @State private var stalkerPortalUrl = ""
    @State private var stalkerMacAddress = ""
    @State private var newPlaylistName = ""
    @State private var newPlaylistM3uUrl = ""
    @State private var newPlaylistEpgUrl = ""
    @State private var showProviderSettings = false
    @State private var showGuide = false
    @State private var providerDiagnostics: [IptvProviderDiagnostic] = []
    @State private var isRunningProviderCheck = false
    @State private var previewChannel: IptvChannel?
    @State private var previewProgram: IptvProgram?
    @State private var previewStream: ResolvedStream?
    @State private var previewPlayer: AVPlayer?
    @State private var showFullscreenGuide = false

    var body: some View {
        HStack(spacing: 0) {
            groupRail
                .frame(width: 250)

            VStack(alignment: .leading, spacing: 18) {
                header
                if appState.iptv.channels.isEmpty || showProviderSettings {
                    setupPanel
                }
                if !appState.iptv.channels.isEmpty {
                    liveMiniPlayer
                    showGuide ? AnyView(epgGuide) : AnyView(channelGrid)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            m3uUrl = appState.iptv.state.m3uUrl
            epgUrl = appState.iptv.state.epgUrl
            stalkerPortalUrl = appState.iptv.state.stalkerPortalUrl
            stalkerMacAddress = appState.iptv.state.stalkerMacAddress
            if let first = appState.iptv.editablePlaylists().first {
                m3uUrl = first.m3uUrl
                epgUrl = first.epgUrl
            }
            if appState.iptv.channels.isEmpty &&
                (!appState.iptv.state.m3uUrl.isEmpty || !appState.iptv.state.stalkerPortalUrl.isEmpty) {
                Task { await appState.iptv.reload() }
            }
        }
        .onDisappear {
            previewPlayer?.pause()
            previewPlayer = nil
            previewProgram = nil
        }
        .overlay {
            if showFullscreenGuide {
                fullscreenGuideOverlay
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live TV")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                Text("\(appState.iptv.channels.count) channels synced with ARVIO cloud")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ArvioTheme.textSecondary)
            }

            Spacer()

            Picker("Mode", selection: $showGuide) {
                Text("Cards").tag(false)
                Text("Guide").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            TextField(
                "Search channels",
                text: Binding(
                    get: { appState.iptv.searchText },
                    set: { appState.iptv.searchText = $0 }
                )
            )
                .textInputAutocapitalization(.never)
                .padding(13)
                .frame(width: 300)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                .foregroundStyle(ArvioTheme.textPrimary)

            Button {
                Task { await appState.iptv.reload() }
            } label: {
                SecondaryButton(title: appState.iptv.isLoading ? "Loading" : "Refresh")
            }
            .buttonStyle(.plain)
            .disabled(appState.iptv.isLoading)

            Button {
                showProviderSettings.toggle()
            } label: {
                SecondaryButton(title: showProviderSettings ? "Hide Provider" : "Provider")
            }
            .buttonStyle(.plain)

            if previewChannel != nil {
                Button {
                    showFullscreenGuide = true
                } label: {
                    SecondaryButton(title: "Fullscreen Guide")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var groupRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandMark()
                .padding(.bottom, 16)

            ForEach(appState.iptv.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        appState.iptv.setGroup(group)
                    } label: {
                        HStack {
                            Text(group)
                                .font(.system(size: 16, weight: group == appState.iptv.selectedGroup ? .bold : .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(countLabel(for: group))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ArvioTheme.textTertiary)
                        }
                        .foregroundStyle(group == appState.iptv.selectedGroup ? ArvioTheme.textPrimary : ArvioTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 8).fill(group == appState.iptv.selectedGroup ? ArvioTheme.gold.opacity(0.15) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(group == appState.iptv.selectedGroup ? ArvioTheme.gold.opacity(0.85) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if group == appState.iptv.selectedGroup && group != "All" && group != "Favorites" {
                        HStack(spacing: 8) {
                            Button(appState.iptv.state.favoriteGroups.contains(group) ? "Unfav" : "Fav") {
                                Task { await appState.iptv.toggleFavoriteGroup(group) }
                            }
                            Button("Hide") {
                                Task { await appState.iptv.toggleHiddenGroup(group) }
                            }
                            Button("Up") {
                                Task { await appState.iptv.moveGroup(group, direction: -1) }
                            }
                            Button("Down") {
                                Task { await appState.iptv.moveGroup(group, direction: 1) }
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11, weight: .bold))
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .background(Color.black.opacity(0.28))
        .overlay(Rectangle().fill(ArvioTheme.border).frame(width: 1), alignment: .trailing)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live TV providers")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text("Add the same M3U, Xtream, EPG, and Stalker providers you use on Android. ARVIO stores them in your cloud sync profile.")
                .font(.system(size: 15))
                .foregroundStyle(ArvioTheme.textSecondary)

            if !appState.iptv.editablePlaylists().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlists")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    ForEach(appState.iptv.editablePlaylists()) { playlist in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ArvioTheme.textPrimary)
                                Text([playlist.m3uUrl, playlist.epgUrl.nilIfBlank].compactMap { $0 }.joined(separator: " - "))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ArvioTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(playlist.enabled ? "Enabled" : "Disabled") {
                                Task { await appState.iptv.togglePlaylist(playlist) }
                            }
                            .buttonStyle(.bordered)
                            Button("Remove", role: .destructive) {
                                Task { await appState.iptv.removePlaylist(playlist) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(playlist.enabled ? ArvioTheme.gold.opacity(0.55) : ArvioTheme.border, lineWidth: 1))
                    }
                }
            }

            TextField("M3U URL", text: $m3uUrl)
                .textInputAutocapitalization(.never)
                .settingsField()
            TextField("EPG URL (optional)", text: $epgUrl)
                .textInputAutocapitalization(.never)
                .settingsField()
            TextField("Stalker portal URL (optional)", text: $stalkerPortalUrl)
                .textInputAutocapitalization(.never)
                .settingsField()
            TextField("Stalker MAC address (optional)", text: $stalkerMacAddress)
                .textInputAutocapitalization(.never)
                .settingsField()

            VStack(alignment: .leading, spacing: 10) {
                Text("Add another M3U/Xtream provider")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                HStack(spacing: 10) {
                    TextField("Name", text: $newPlaylistName)
                        .settingsField()
                    TextField("M3U/Xtream URL", text: $newPlaylistM3uUrl)
                        .textInputAutocapitalization(.never)
                        .settingsField()
                    TextField("EPG URL", text: $newPlaylistEpgUrl)
                        .textInputAutocapitalization(.never)
                        .settingsField()
                    Button("Add") {
                        Task {
                            await appState.iptv.addPlaylist(
                                name: newPlaylistName,
                                m3uUrl: newPlaylistM3uUrl,
                                epgUrl: newPlaylistEpgUrl
                            )
                            newPlaylistName = ""
                            newPlaylistM3uUrl = ""
                            newPlaylistEpgUrl = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            HStack {
                Button {
                    Task {
                        await appState.iptv.saveConfig(m3uUrl: m3uUrl, epgUrl: epgUrl)
                        if !stalkerPortalUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !stalkerMacAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await appState.iptv.saveStalkerConfig(portalUrl: stalkerPortalUrl, macAddress: stalkerMacAddress)
                        }
                    }
                } label: {
                    PrimaryButton(title: "Save and Load")
                }
                .buttonStyle(.plain)

                if appState.iptv.isLoading {
                    Text(appState.iptv.progressMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }

                Button {
                    Task { await runProviderCheck() }
                } label: {
                    SecondaryButton(title: isRunningProviderCheck ? "Checking" : "Run Provider Check")
                }
                .buttonStyle(.plain)
                .disabled(isRunningProviderCheck)
            }

            if let error = appState.iptv.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            if !providerDiagnostics.isEmpty {
                VStack(spacing: 8) {
                    ForEach(providerDiagnostics) { result in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(result.isSuccess ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(result.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ArvioTheme.textPrimary)
                                .frame(width: 130, alignment: .leading)
                            Text(result.status)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(result.isSuccess ? Color.green.opacity(0.95) : Color.orange.opacity(0.95))
                                .frame(width: 72, alignment: .leading)
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
        }
        .padding(22)
        .frame(maxWidth: 720, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private var channelGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(appState.iptv.visibleChannels) { channel in
                    ChannelTile(channel: channel, guide: appState.iptv.nowNextByChannelId[channel.id]) {
                        selectChannel(channel)
                    }
                }
            }
            .padding(.bottom, 36)
        }
        .overlay(alignment: .topLeading) {
            if let error = appState.iptv.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
            }
        }
    }

    private var epgGuide: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.iptv.visibleChannels) { channel in
                    HStack(spacing: 10) {
                        ChannelGuideLabel(channel: channel)
                            .onTapGesture {
                                selectChannel(channel)
                            }
                        let programs = guidePrograms(for: channel)
                        if programs.isEmpty {
                            Text(appState.iptv.nowNextByChannelId[channel.id]?.now?.title ?? "No guide data")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ArvioTheme.textTertiary)
                                .frame(width: 760, height: 58, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                        } else {
                            ForEach(programs) { program in
                                let isCatchup = isCatchupProgram(channel, program)
                                ProgramBlock(program: program, isCatchupSupported: isCatchup)
                                    .onTapGesture {
                                        if isCatchup {
                                            playCatchup(channel, program)
                                        } else {
                                            selectChannel(channel)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 36)
        }
        .overlay(alignment: .topLeading) {
            if appState.iptv.programsByChannelId.isEmpty {
                Text("Guide data loads when your provider supplies XMLTV/EPG.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
            }
        }
    }

    private func countLabel(for group: String) -> String {
        if group == "All" { return "\(appState.iptv.channels.count)" }
        if group == "Favorites" { return "\(appState.iptv.state.favoriteChannels.count)" }
        return "\(appState.iptv.channels.filter { $0.group == group }.count)"
    }

    private func guidePrograms(for channel: IptvChannel) -> [IptvProgram] {
        let now = Date()
        let start = channel.supportsCatchup
            ? now.addingTimeInterval(-Double(max(min(channel.catchupDays, 7), 2)) * 24 * 60 * 60)
            : now
        let end = now.addingTimeInterval(60 * 60 * 6)
        return (appState.iptv.programsByChannelId[channel.id] ?? [])
            .filter { $0.stop > start && $0.start < end }
            .suffix(16)
            .map { $0 }
    }

    private var liveMiniPlayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    if let previewPlayer {
                        VideoPlayer(player: previewPlayer)
                    } else {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.black.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image("ARVIOAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 68)
                            .opacity(0.72)
                    }
                }
                .frame(width: 280, height: 158)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(previewProgram == nil ? "LIVE" : "REPLAY")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(ArvioTheme.gold))
                        Text(previewChannel?.group ?? appState.iptv.selectedGroup)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ArvioTheme.textTertiary)
                    }
                    Text(previewChannel?.name ?? "Select a channel")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .lineLimit(1)
                    Text(currentProgramText(for: previewChannel))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ArvioTheme.gold)
                        .lineLimit(1)
                    Text(nextProgramText(for: previewChannel))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                        .lineLimit(1)

                    if let channel = previewChannel {
                        let recent = recentCatchupPrograms(for: channel)
                        if !recent.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(recent) { program in
                                    Button {
                                        playCatchup(channel, program)
                                    } label: {
                                        Text("Replay \(programTime(program.start))")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(ArvioTheme.textPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Color.white.opacity(0.08)))
                                            .overlay(Capsule().stroke(ArvioTheme.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            playPreviewFullscreen()
                        } label: {
                            PrimaryButton(title: "Watch Fullscreen")
                        }
                        .buttonStyle(.plain)
                        .disabled(previewStream == nil)

                        Button {
                            showFullscreenGuide = true
                        } label: {
                            SecondaryButton(title: "Open Guide")
                        }
                        .buttonStyle(.plain)

                        if let channel = previewChannel {
                            Button {
                                Task { await appState.iptv.toggleFavorite(channel) }
                            } label: {
                                SecondaryButton(title: appState.iptv.state.favoriteChannels.contains(channel.id) ? "Saved" : "Save")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }

    private var fullscreenGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Live Guide")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(previewChannel?.name ?? "\(appState.iptv.visibleChannels.count) channels")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ArvioTheme.textSecondary)
                    }
                    Spacer()
                    Button("Close") {
                        showFullscreenGuide = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArvioTheme.gold)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            if let previewPlayer {
                                VideoPlayer(player: previewPlayer)
                            } else {
                                Color.black
                                Image("ARVIOAppIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 90, height: 90)
                                    .opacity(0.75)
                            }
                        }
                        .frame(width: 430, height: 242)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.gold.opacity(0.6), lineWidth: 1))

                        Text(currentProgramText(for: previewChannel))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(ArvioTheme.gold)
                            .lineLimit(2)
                        Text(nextProgramText(for: previewChannel))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ArvioTheme.textSecondary)
                            .lineLimit(2)
                        Button("Watch Fullscreen") {
                            playPreviewFullscreen()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                        .disabled(previewStream == nil)
                    }
                    .frame(width: 430, alignment: .topLeading)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.iptv.visibleChannels) { channel in
                                Button {
                                    selectChannel(channel)
                                } label: {
                                    fullscreenGuideRow(channel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
    }

    private func fullscreenGuideRow(_ channel: IptvChannel) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.logo.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image("ARVIOAppIcon").resizable().scaledToFit().opacity(0.72)
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(1)
                Text(currentProgramText(for: channel))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArvioTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(channel.group)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(ArvioTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(channel.id == previewChannel?.id ? ArvioTheme.gold.opacity(0.14) : Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(channel.id == previewChannel?.id ? ArvioTheme.gold.opacity(0.85) : ArvioTheme.border, lineWidth: 1))
    }

    private func selectChannel(_ channel: IptvChannel) {
        appState.iptv.markOpened(channel)
        previewChannel = channel
        previewProgram = nil
        let stream = liveStream(for: channel)
        previewStream = stream
        configurePreviewPlayer(stream)
    }

    private func playCatchup(_ channel: IptvChannel, _ program: IptvProgram) {
        appState.iptv.markOpened(channel)
        previewChannel = channel
        previewProgram = program
        let stream = channel.resolvedCatchupStream(
            program: program,
            customUserAgent: appState.settings.profileSettings.customUserAgent
        )
        previewStream = stream
        configurePreviewPlayer(stream)
    }

    private func playPreviewFullscreen() {
        guard let stream = previewStream else { return }
        appState.selectedStream = stream
    }

    private func configurePreviewPlayer(_ stream: ResolvedStream) {
        previewPlayer?.pause()
        guard let url = stream.url else {
            previewPlayer = nil
            return
        }
        let asset = stream.requestHeaders.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: [AVURLAssetHTTPHeaderFieldsKey: stream.requestHeaders])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        previewPlayer = player
        player.isMuted = true
        player.play()
    }

    private func currentProgramText(for channel: IptvChannel?) -> String {
        if let previewProgram, channel?.id == previewChannel?.id {
            return "Replay: \(previewProgram.title)"
        }
        guard let channel else { return "Choose a channel to preview while browsing." }
        return appState.iptv.nowNextByChannelId[channel.id]?.now?.title ?? "Now playing"
    }

    private func nextProgramText(for channel: IptvChannel?) -> String {
        if let previewProgram, channel?.id == previewChannel?.id {
            return "\(programTime(previewProgram.start)) - \(programTime(previewProgram.stop))"
        }
        guard let channel else { return "Guide and channel controls stay available." }
        if let next = appState.iptv.nowNextByChannelId[channel.id]?.next {
            return "Next: \(next.title)"
        }
        return "No upcoming programme information"
    }

    private func isCatchupProgram(_ channel: IptvChannel, _ program: IptvProgram) -> Bool {
        channel.supportsCatchup && program.stop <= Date() && channel.catchupUrl(for: program) != nil
    }

    private func recentCatchupPrograms(for channel: IptvChannel) -> [IptvProgram] {
        Array((appState.iptv.programsByChannelId[channel.id] ?? [])
            .filter { isCatchupProgram(channel, $0) }
            .suffix(3)
            .reversed())
    }

    private func programTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func runProviderCheck() async {
        isRunningProviderCheck = true
        defer { isRunningProviderCheck = false }
        providerDiagnostics = await appState.iptv.runProviderDiagnostics(
            m3uUrl: m3uUrl,
            epgUrl: epgUrl,
            stalkerPortalUrl: stalkerPortalUrl,
            stalkerMacAddress: stalkerMacAddress
        )
    }

    private func liveStream(for channel: IptvChannel) -> ResolvedStream {
        channel.resolvedLiveStream(
            customUserAgent: appState.settings.profileSettings.customUserAgent
        )
    }
}

private struct ChannelGuideLabel: View {
    let channel: IptvChannel

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: channel.logo.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image("ARVIOAppIcon").resizable().scaledToFit().opacity(0.75)
                }
            }
            .frame(width: 34, height: 34)
            Text(channel.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
                .lineLimit(2)
        }
        .frame(width: 220, height: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.26)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}

private struct ProgramBlock: View {
    let program: IptvProgram
    var isCatchupSupported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(program.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(1)
                if isCatchupSupported {
                    Text("Replay")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ArvioTheme.gold))
                }
            }
            Text("\(time(program.start)) - \(time(program.stop))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ArvioTheme.textTertiary)
        }
        .frame(width: blockWidth, height: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }

    private var isNow: Bool {
        program.start <= Date() && program.stop > Date()
    }

    private var backgroundColor: Color {
        if isNow { return ArvioTheme.gold.opacity(0.16) }
        if isCatchupSupported { return Color.white.opacity(0.075) }
        return ArvioTheme.panel
    }

    private var borderColor: Color {
        if isNow || isCatchupSupported { return ArvioTheme.gold.opacity(0.85) }
        return ArvioTheme.border
    }

    private var blockWidth: CGFloat {
        let minutes = max(30, min(180, program.stop.timeIntervalSince(program.start) / 60))
        return CGFloat(minutes * 3.2)
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct ChannelTile: View {
    @EnvironmentObject private var appState: AppState
    let channel: IptvChannel
    let guide: IptvNowNext?
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AsyncImage(url: channel.logo.flatMap(URL.init(string:))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Image("ARVIOAppIcon").resizable().scaledToFit().opacity(0.8)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.28)))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(channel.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ArvioTheme.textPrimary)
                            .lineLimit(2)
                        Text(channel.group)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ArvioTheme.textTertiary)
                            .lineLimit(1)
                        if let title = guide?.now?.title {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ArvioTheme.gold)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }

                HStack {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(ArvioTheme.gold))
                    Spacer()
                    Button {
                        Task { await appState.iptv.toggleFavorite(channel) }
                    } label: {
                        Text(appState.iptv.state.favoriteChannels.contains(channel.id) ? "Saved" : "Save")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                }
                if let next = guide?.next {
                    Text("Next: \(next.title)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ArvioTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(minHeight: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
