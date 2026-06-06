import SwiftUI

enum ArvioTab: String, CaseIterable {
    case home = "Home"
    case movies = "Movies"
    case series = "Series"
    case liveTV = "Live TV"
    case watchlist = "Watchlist"
    case search = "Search"
    case settings = "Settings"

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .movies: return "2"
        case .series: return "3"
        case .liveTV: return "4"
        case .watchlist: return "5"
        case .search: return "6"
        case .settings: return "7"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "tv.fill"
        case .liveTV: return "dot.radiowaves.left.and.right"
        case .watchlist: return "bookmark.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: ArvioTab = .home

    var body: some View {
        ZStack {
            ArvioTheme.background.ignoresSafeArea()

            LinearGradient(
                colors: [Color(hex: "#0b1b2a").opacity(0.65), Color.black.opacity(0.1), Color.black.opacity(0.72)],
                startPoint: .topTrailing,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let stream = appState.selectedStream {
                PlayerView(stream: stream)
            } else if let media = appState.selectedMedia {
                DetailsView(item: media)
            } else if let catalog = appState.selectedCatalog {
                CatalogDetailView(config: catalog)
            } else {
                HStack(spacing: 0) {
                    SidebarNavigation(selectedTab: $selectedTab)
                        .frame(width: 224)

                    Group {
                        switch selectedTab {
                        case .home:
                            HomeView()
                        case .movies:
                            MediaBrowserView(kind: .movie)
                        case .series:
                            MediaBrowserView(kind: .series)
                        case .liveTV:
                            LiveTVView()
                        case .watchlist:
                            WatchlistView()
                        case .search:
                            SearchView()
                        case .settings:
                            SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if appState.profiles.isSwitcherVisible {
                ProfileSelectionView()
                    .transition(.opacity)
            }
        }
    }
}

struct SidebarNavigation: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: ArvioTab

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                appState.profiles.isSwitcherVisible = true
            } label: {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARVIO")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(ArvioTheme.textPrimary)
                        Text(appState.profiles.activeProfile?.name ?? "Profile")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ArvioTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    ProfileDot(profile: appState.profiles.activeProfile)
                }
                .padding(.bottom, 10)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ArvioTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 24)
                            Text(tab.rawValue)
                                .font(.system(size: 16, weight: selectedTab == tab ? .bold : .semibold))
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(selectedTab == tab ? ArvioTheme.textPrimary : ArvioTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? ArvioTheme.gold.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? ArvioTheme.gold.opacity(0.9) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(true)
                    .hoverEffect(.highlight)
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: [.command])
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.auth.isAuthenticated ? "Cloud connected" : "Cloud disconnected")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(appState.auth.isAuthenticated ? Color.green.opacity(0.92) : ArvioTheme.textTertiary)
                Text(appState.trakt.isConnected ? "Trakt active" : "Trakt not linked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ArvioTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
        }
        .padding(18)
        .background(Color.black.opacity(0.34))
        .overlay(Rectangle().fill(ArvioTheme.border).frame(width: 1), alignment: .trailing)
    }
}

struct TopNavigation: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: ArvioTab

    var body: some View {
        HStack(spacing: 20) {
            Button {
                appState.profiles.isSwitcherVisible = true
            } label: {
                HStack(spacing: 10) {
                    ProfileDot(profile: appState.profiles.activeProfile)
                    BrandMark()
                }
            }
            .buttonStyle(.plain)
            .focusable(true)
            .hoverEffect(.highlight)

            ForEach(ArvioTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? ArvioTheme.textPrimary : ArvioTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? ArvioTheme.gold.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? ArvioTheme.gold : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .focusable(true)
                .hoverEffect(.highlight)
                .keyboardShortcut(tab.keyboardShortcut, modifiers: [.command])
            }

            Spacer()

            Text("ARVIO")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ArvioTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct BrandMark: View {
    var body: some View {
        Image("ARVIOAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProfileDot: View {
    let profile: ArvioProfile?

    var body: some View {
        Circle()
            .fill(Color(hex: profile?.swiftUIColorHex ?? "#3B82F6"))
            .frame(width: 34, height: 34)
            .overlay {
                Text(String((profile?.name ?? "A").prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.white)
            }
            .overlay(Circle().stroke(ArvioTheme.gold.opacity(0.85), lineWidth: 1))
    }
}
