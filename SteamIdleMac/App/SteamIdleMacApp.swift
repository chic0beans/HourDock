import AppKit
import SwiftUI

enum MainWindowIdentifier {
    static let value = NSUserInterfaceItemIdentifier("com.steamidlemac.mainWindow")
}

@main
struct SteamIdleMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var appState = AppState()
    @StateObject private var updater = SparkleUpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.bootstrap()
                    AppDelegate.shared?.register(appState: appState)
                    updater.probeForUpdatesIfNeeded()
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.contentView?.subviews.first is NSHostingView<AnyView> || $0.canBecomeMain }) {
                            window.identifier = MainWindowIdentifier.value
                            window.setFrameAutosaveName("SteamIdleMacMainWindow")
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
        }

        MenuBarExtra {
            MenuBarDashboard()
                .environmentObject(appState)
                .environmentObject(updater)
        } label: {
            let count = appState.idleManager.activeSessions.count
            ZStack(alignment: .topTrailing) {
                Image(systemName: count > 0 ? "gamecontroller.fill" : "gamecontroller")
                if updater.isUpdateAvailable {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.8)
                        )
                        .offset(x: 4, y: -3)
                        .accessibilityLabel(
                            updater.availableUpdateDisplayVersion.map { "Update \($0) available" } ?? "Update available"
                        )
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    private weak var appState: AppState?

    func register(appState: AppState) {
        self.appState = appState
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let appState else { return }
        Task { @MainActor in
            guard appState.onboardingCompleted,
                  !appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !appState.steamID64.isEmpty else { return }
            await appState.refreshProfileFromNetwork()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .steamIdleAppWillTerminate, object: nil)
        appState?.idleManager.cleanupOnQuit()
    }
}
