import Foundation

enum IdleSnapshotStore {
    static let appGroupID = IdleSnapshotReader.appGroupID
    static let storageKey = IdleSnapshotReader.storageKey

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(sessions: [ActiveIdleSession], games: [Game]) {
        let entries = sessions.map { session -> IdleSnapshotEntry in
            let game = games.first { $0.appid == session.appid }
            let url = game?.widgetIconURL ?? game?.iconImageURL
            return IdleSnapshotEntry(
                appid: session.appid,
                name: game?.name ?? session.name,
                iconURLString: url?.absoluteString
            )
        }
        let snapshot = IdleSnapshot(updatedAt: Date(), sessions: entries)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }
}
