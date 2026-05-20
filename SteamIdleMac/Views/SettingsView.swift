import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var saveError: String?

    var body: some View {
        Form {
            Section("General") {
                Button("Show setup again") {
                    appState.resetOnboarding()
                    dismiss()
                }
            }

            Section("Steam Web API") {
                SecureField("API Key", text: $appState.apiKey)
                Link("Get an API key", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                    .font(.caption)
            }

            Section("Account") {
                TextField("SteamID64", text: $appState.steamID64)
                Text("Auto-detected from Steam login when empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Picker("Banner style", selection: Binding(
                    get: { appState.bannerStyle },
                    set: { appState.bannerStyle = $0 }
                )) {
                    ForEach(BannerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        do {
            try appState.saveSettings()
            saveError = nil
            dismiss()
            Task { await appState.refreshLibrary(force: true) }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
