import AppKit

struct SteamRunningService {
    /// Bundle identifiers we treat as the official Steam client. Substring matches like
    /// `bid.contains("steam")` falsely flag third-party apps; whitelist explicitly.
    private static let steamBundleIDs: Set<String> = [
        "com.valvesoftware.steam",
        "com.valvesoftware.steam.helper",
    ]

    func isSteamRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let bid = app.bundleIdentifier?.lowercased() else { return false }
            if Self.steamBundleIDs.contains(bid) { return true }
            // Fallback for sideloaded/dev builds that prefix the bundle id.
            return bid.hasPrefix("com.valvesoftware.steam")
        }
    }
}
