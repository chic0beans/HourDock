import Foundation

/// Shared between app and widget extension (App Group).
///
/// NOTE: This file is intentionally duplicated with `Shared/IdleSnapshotShared.swift`.
/// The Xcode widget target (built via `project.yml`) sources `Shared/`, while the
/// `swift build` package target sources only `SteamIdleMac/`. Keep the two copies in
/// lockstep when changing this file.
struct IdleSnapshotEntry: Codable, Identifiable, Hashable {
    let appid: UInt64
    let name: String
    let iconURLString: String?

    var id: UInt64 { appid }

    var iconURL: URL? {
        guard let iconURLString else { return nil }
        return URL(string: iconURLString)
    }
}

struct IdleSnapshot: Codable {
    let updatedAt: Date
    let sessions: [IdleSnapshotEntry]

    static let empty = IdleSnapshot(updatedAt: Date(), sessions: [])
}

enum IdleSnapshotReader {
    static let appGroupID = "group.com.steamidlemac.shared"
    static let storageKey = "activeIdles.json"

    static func load() -> IdleSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(IdleSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }
}
