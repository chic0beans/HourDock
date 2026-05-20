import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var saveError: String?
    @State private var isRefreshing = false
    @State private var animateBackdrop = false
    @State private var isSteamIDLocked = true
    @FocusState private var apiKeyFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.08, green: 0.14, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.blue.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 42)
                .offset(x: animateBackdrop ? 190 : -170, y: animateBackdrop ? -150 : 120)

            Circle()
                .fill(Color.green.opacity(0.13))
                .frame(width: 280, height: 280)
                .blur(radius: 36)
                .offset(x: animateBackdrop ? -210 : 170, y: animateBackdrop ? 130 : -130)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 14) {
                        settingsCard(title: "Steam Web API", subtitle: "Saved securely in Keychain") {
                            VStack(alignment: .leading, spacing: 10) {
                                SecureField("API Key", text: $appState.apiKey)
                                    .focused($apiKeyFocused)
                                    .styledGlassInput()

                                HStack {
                                    if let url = AppLinks.steamAPIKey {
                                        Link("Get an API key", destination: url)
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Text(appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : "Configured")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(
                                            appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? Color.secondary
                                                : Color.green
                                        )
                                }
                            }
                        }

                        settingsCard(title: "Account", subtitle: "Steam profile source") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    TextField("SteamID64", text: $appState.steamID64)
                                        .styledGlassInput(
                                            dimmed: isSteamIDLocked,
                                            accent: isSteamIDLocked ? .secondary : .accentColor
                                        )
                                        .disabled(isSteamIDLocked)

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            isSteamIDLocked.toggle()
                                        }
                                        if isSteamIDLocked {
                                            appState.detectSteamIDFromActiveAccount()
                                        }
                                    } label: {
                                        Label(
                                            isSteamIDLocked ? "Locked" : "Unlocked",
                                            systemImage: isSteamIDLocked ? "lock.fill" : "lock.open.fill"
                                        )
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(isSteamIDLocked ? Color.white.opacity(0.10) : Color.accentColor.opacity(0.25))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(isSteamIDLocked ? Color.white.opacity(0.26) : Color.accentColor.opacity(0.55), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help(isSteamIDLocked ? "Unlock to edit SteamID manually" : "Lock to use the detected active Steam account")
                                }
                                Text("Leave empty to auto-detect from Steam loginusers.vdf.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        settingsCard(title: "Display", subtitle: "Customize floating idle banner appearance.") {
                            Picker("Banner style", selection: Binding(
                                get: { appState.bannerStyle },
                                set: { appState.bannerStyle = $0 }
                            )) {
                                ForEach(BannerStyle.allCases) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        settingsCard(title: "Maintenance", subtitle: "Refresh data and onboarding state.") {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    refreshNow()
                                } label: {
                                    HStack {
                                        Label("Refresh library and profile", systemImage: "arrow.clockwise")
                                        Spacer()
                                        if isRefreshing {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                .disabled(isRefreshing || appState.isLoadingLibrary || appState.isLoadingProfile)

                                Button("Show setup again") {
                                    appState.resetOnboarding()
                                    dismiss()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                            }
                        }

                        if let saveError {
                            Text(saveError)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }

                Divider()

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.accentColor.opacity(0.9)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 560)
        .onAppear {
            appState.detectSteamIDFromActiveAccount()
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateBackdrop = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.16)))
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Everything in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    statusPill(text: appState.isLoadingLibrary ? "Refreshing library" : "Library ready")
                    statusPill(text: appState.isLoadingProfile ? "Refreshing profile" : "Profile synced")
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private func statusPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.white.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private func refreshNow() {
        isRefreshing = true
        Task { @MainActor in
            await appState.refreshLibrary(force: true)
            await appState.refreshProfileFromNetwork(minInterval: 0)
            isRefreshing = false
        }
    }

    private func save() {
        do {
            try appState.saveSettings()
            saveError = nil
            let state = appState
            Task { @MainActor in
                await state.refreshLibrary(force: true)
                await state.refreshProfileFromNetwork(minInterval: 0)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private extension View {
    func styledGlassInput(dimmed: Bool = false, accent: Color = Color.white) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if dimmed {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dimmed ? Color.white.opacity(0.24) : accent.opacity(0.16), lineWidth: 1)
            )
    }
}
