import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var bannerManager = IdleBannerWindowManager()

    var body: some View {
        Group {
            if !appState.onboardingCompleted {
                OnboardingView()
            } else if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SetupView()
            } else {
                GameLibraryView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .onAppear { configureWindowLevels() }
        .onChange(of: appState.bannerStyle) { _ in resyncBanners() }
        .onChange(of: appState.idleManager.activeSessions.map(\.appid)) { _ in
            resyncBanners()
        }
        .onDisappear {
            bannerManager.closeAll()
            appState.idleManager.cleanupOnQuit()
        }
    }

    private func resyncBanners() {
        bannerManager.sync(
            with: appState.idleManager.activeSessions,
            games: appState.games,
            style: appState.bannerStyle
        ) { appid in
            appState.stopIdle(appid: appid)
        }
        configureWindowLevels()
    }

    /// Main window stays above idle banners without floating over other apps.
    private func configureWindowLevels() {
        for window in NSApp.windows {
            if window is NSPanel {
                window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            } else if window.contentView != nil {
                window.level = .normal
            }
        }
    }
}
