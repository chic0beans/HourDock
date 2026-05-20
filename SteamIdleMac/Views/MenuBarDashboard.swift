import AppKit
import SwiftUI

struct MenuBarDashboard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updater: SparkleUpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(.vertical, 8)
        .frame(width: 320)
    }

    private var header: some View {
        let count = appState.idleManager.activeSessions.count
        return HStack {
            Image(systemName: count > 0 ? "bolt.fill" : "moon.zzz")
                .foregroundStyle(count > 0 ? .green : .secondary)
            Text("\(count)/\(IdleProcessManager.maxConcurrent) idling")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        let sessions = appState.idleManager.activeSessions
        if sessions.isEmpty {
            HStack {
                Spacer()
                Text("Nothing idling")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 14)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sessions) { session in
                        DashboardRow(session: session,
                                     game: appState.games.first { $0.appid == session.appid }) {
                            appState.stopIdle(game: Game(appid: session.appid,
                                                         name: session.name,
                                                         playtimeForever: 0))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if updater.isUpdateAvailable {
                menuButton(
                    updater.availableUpdateDisplayVersion.map { "Update available (\($0))" } ?? "Update available"
                ) {
                    updater.checkForUpdates()
                }
            }
            menuButton("Show window") {
                NSApp.activate(ignoringOtherApps: true)
                let candidates = NSApp.windows.filter { window in
                    !(window is NSPanel) && window.canBecomeMain
                }
                let tagged = candidates.first { $0.identifier == MainWindowIdentifier.value }
                let target = tagged ?? candidates.first
                target?.makeKeyAndOrderFront(nil)
            }
            if !appState.selectedAppIDs.isEmpty {
                menuButton("Start selected (\(appState.selectedAppIDs.count))") {
                    appState.startIdleForSelection()
                }
            }
            if !appState.idleManager.activeSessions.isEmpty {
                menuButton("Regrid banners") {
                    NotificationCenter.default.post(name: .regridIdleBanners, object: nil)
                }
                menuButton("Stop all") { appState.stopAllIdling() }
            }
            menuButton("Check for updates...") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
            menuButton("Quit HourDock") {
                appState.idleManager.cleanupOnQuit()
                NSApp.terminate(nil)
            }
        }
        .padding(.top, 4)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardRow: View {
    let session: ActiveIdleSession
    let game: Game?
    let onStop: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(game?.name ?? session.name)
                    .font(.callout)
                    .lineLimit(1)
                Text("Idling")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .opacity(hovering ? 1 : 0.75)
            .help("Stop \(game?.name ?? session.name)")
            .accessibilityLabel("Stop \(game?.name ?? session.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.secondary.opacity(0.15) : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if let g = game {
            CachedRemoteImage(url: g.iconImageURL, contentMode: .fill) {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }
}
