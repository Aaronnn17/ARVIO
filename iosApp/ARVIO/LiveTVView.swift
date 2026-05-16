import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject private var appState: AppState
    @State private var m3uUrl = ""
    @State private var epgUrl = ""

    var body: some View {
        HStack(spacing: 0) {
            groupRail
                .frame(width: 250)

            VStack(alignment: .leading, spacing: 18) {
                header
                if appState.iptv.channels.isEmpty {
                    setupPanel
                } else {
                    channelGrid
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            m3uUrl = appState.iptv.state.m3uUrl
            epgUrl = appState.iptv.state.epgUrl
            if appState.iptv.channels.isEmpty && !appState.iptv.state.m3uUrl.isEmpty {
                Task { await appState.iptv.reload() }
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
        }
    }

    private var groupRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandMark()
                .padding(.bottom, 16)

            ForEach(appState.iptv.groups, id: \.self) { group in
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
            }

            Spacer()
        }
        .padding(24)
        .background(Color.black.opacity(0.28))
        .overlay(Rectangle().fill(ArvioTheme.border).frame(width: 1), alignment: .trailing)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IPTV playlist")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            Text("Add the same M3U and EPG URLs you use on Android. ARVIO stores them in your cloud sync profile.")
                .font(.system(size: 15))
                .foregroundStyle(ArvioTheme.textSecondary)

            TextField("M3U URL", text: $m3uUrl)
                .textInputAutocapitalization(.never)
                .settingsField()
            TextField("EPG URL (optional)", text: $epgUrl)
                .textInputAutocapitalization(.never)
                .settingsField()

            HStack {
                Button {
                    Task { await appState.iptv.saveConfig(m3uUrl: m3uUrl, epgUrl: epgUrl) }
                } label: {
                    PrimaryButton(title: "Save and Load")
                }
                .buttonStyle(.plain)

                if appState.iptv.isLoading {
                    Text(appState.iptv.progressMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArvioTheme.textSecondary)
                }
            }

            if let error = appState.iptv.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
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
                    ChannelTile(channel: channel)
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

    private func countLabel(for group: String) -> String {
        if group == "All" { return "\(appState.iptv.channels.count)" }
        if group == "Favorites" { return "\(appState.iptv.state.favoriteChannels.count)" }
        return "\(appState.iptv.channels.filter { $0.group == group }.count)"
    }
}

private struct ChannelTile: View {
    @EnvironmentObject private var appState: AppState
    let channel: IptvChannel

    var body: some View {
        Button {
            play()
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
            }
            .padding(14)
            .frame(minHeight: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func play() {
        appState.iptv.markOpened(channel)
        appState.selectedStream = ResolvedStream(
            addonName: "Live TV",
            sourceName: channel.group,
            title: channel.name,
            quality: "Live",
            size: "",
            url: URL(string: channel.streamUrl),
            isPlayable: true,
            resumePositionSeconds: nil
        )
    }
}
