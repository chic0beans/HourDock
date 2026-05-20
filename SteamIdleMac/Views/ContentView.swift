import SwiftUI
import AppKit

extension Notification.Name {
    static let steamIdleAppWillTerminate = Notification.Name("com.steamidlemac.app.willTerminate")
    static let regridIdleBanners = Notification.Name("com.steamidlemac.app.regridIdleBanners")
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var bannerManager = IdleBannerWindowManager()
    @State private var activeAppIDsSnapshot: [UInt64] = []

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
        .onAppear {
            activeAppIDsSnapshot = appState.idleManager.activeSessions.map(\.appid)
            resyncBanners(sessions: appState.idleManager.activeSessions)
        }
        .onChange(of: appState.bannerStyle) { _ in
            resyncBanners(sessions: appState.idleManager.activeSessions)
        }
        .onReceive(appState.idleManager.$activeSessions) { sessions in
            let ids = sessions.map(\.appid)
            guard ids != activeAppIDsSnapshot else { return }
            activeAppIDsSnapshot = ids
            // `@Published` emits before the backing property is committed; use the emitted
            // value directly so banner sync reflects starts/stops immediately.
            resyncBanners(sessions: sessions)
        }
        .onReceive(NotificationCenter.default.publisher(for: .steamIdleAppWillTerminate)) { _ in
            bannerManager.closeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .regridIdleBanners)) { _ in
            bannerManager.regrid()
        }
    }

    private func resyncBanners(sessions: [ActiveIdleSession]) {
        bannerManager.sync(
            with: sessions,
            games: appState.games,
            style: appState.bannerStyle
        ) { appid in
            appState.stopIdle(appid: appid)
        }
    }
}
