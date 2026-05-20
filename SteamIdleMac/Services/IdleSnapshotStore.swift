import Foundation

enum IdleSnapshotStore {
    static let appGroupID = IdleSnapshotReader.appGroupID
    static let storageKey = IdleSnapshotReader.storageKey

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(sessions: [ActiveIdleSession], games: [Game]) {
        // O(1) lookup instead of scanning `games` per session.
        let gamesByID = Dictionary(uniqueKeysWithValues: games.map { ($0.appid, $0) })
        let entries = sessions.map { session -> IdleSnapshotEntry in
            let game = gamesByID[session.appid]
            let url: URL? = game.flatMap { $0.widgetIconURL } ?? game.flatMap { $0.iconImageURL }
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
