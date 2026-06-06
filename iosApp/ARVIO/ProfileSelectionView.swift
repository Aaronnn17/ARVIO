import SwiftUI

struct ProfileSelectionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            ArvioTheme.background.ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color(hex: "#07131f").opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    BrandMark()
                    Spacer()
                    Button("Close") {
                        appState.profiles.isSwitcherVisible = false
                    }
                    .buttonStyle(.bordered)
                }

                Text("Who's watching?")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(ArvioTheme.textPrimary)

                HStack(spacing: 22) {
                    ForEach(appState.profiles.profiles) { profile in
                        profileButton(profile)
                    }
                    addProfileCard
                }

                if let error = appState.profiles.errorMessage {
                    Text(error)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
            }
            .padding(48)

            if appState.profiles.pendingLockedProfile != nil {
                pinPanel
            }
        }
    }

    private func profileButton(_ profile: ArvioProfile) -> some View {
        VStack(spacing: 14) {
            Button {
                appState.profiles.requestSelect(profile)
            } label: {
                VStack(spacing: 12) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: profile.swiftUIColorHex), Color.white.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 118, height: 118)
                        .overlay {
                            Text(String(profile.name.prefix(1)).uppercased())
                                .font(.system(size: 44, weight: .black))
                                .foregroundStyle(Color.white)
                        }
                        .overlay(Circle().stroke(profile.id == appState.profiles.activeProfile?.id ? ArvioTheme.gold : ArvioTheme.border, lineWidth: 3))

                    Text(profile.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if appState.profiles.profiles.count > 1 {
                Button("Delete") {
                    Task { await appState.profiles.delete(profile) }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 150)
    }

    private var addProfileCard: some View {
        VStack(spacing: 12) {
            TextField("Name", text: Binding(
                get: { appState.profiles.newProfileName },
                set: { appState.profiles.newProfileName = $0 }
            ))
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(width: 150)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))

            Button {
                Task { await appState.profiles.createProfile() }
            } label: {
                SecondaryButton(title: "Add Profile")
            }
            .buttonStyle(.plain)
        }
        .frame(width: 170)
    }

    private var pinPanel: some View {
        VStack(spacing: 16) {
            Text("Enter PIN")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)
            SecureField("PIN", text: Binding(
                get: { appState.profiles.pinEntry },
                set: { appState.profiles.pinEntry = $0 }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .settingsField()
            .frame(width: 220)
            HStack {
                Button("Cancel") {
                    appState.profiles.pendingLockedProfile = nil
                }
                .buttonStyle(.bordered)
                Button("Unlock") {
                    appState.profiles.confirmPin()
                }
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}
