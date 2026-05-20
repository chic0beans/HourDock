import Foundation

enum SteamPathError: LocalizedError {
    case steamNotFound
    case loginUsersNotFound
    case noRecentUser

    var errorDescription: String? {
        switch self {
        case .steamNotFound:
            return "Steam installation not found. Install Steam for macOS and sign in once."
        case .loginUsersNotFound:
            return "Could not read Steam login configuration."
        case .noRecentUser:
            return "No recent Steam user found in loginusers.vdf."
        }
    }
}

struct SteamPathService {
    static let defaultSteamRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)

    static let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SteamIdleMac", isDirectory: true)

    func steamRoot() throws -> URL {
        let url = Self.defaultSteamRoot
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SteamPathError.steamNotFound
        }
        return url
    }

    /// Directory containing steamclient.dylib (required for SteamAPI_Init on macOS).
    func steamClientLibraryPath() throws -> URL {
        let candidates = [
            try steamRoot().appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Steam.app/Contents/MacOS"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.appendingPathComponent("steamclient.dylib").path) {
            return url
        }
        throw SteamPathError.steamNotFound
    }

    func loginUsersURL() throws -> URL {
        let url = try steamRoot().appendingPathComponent("config/loginusers.vdf")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SteamPathError.loginUsersNotFound
        }
        return url
    }

    func detectSteamID64() throws -> String {
        let contents = try String(contentsOf: loginUsersURL(), encoding: .utf8)
        let blocks = parseVDFUsers(contents)
        if let recent = blocks.first(where: { $0.mostRecent }) {
            return recent.steamID
        }
        if let first = blocks.first {
            return first.steamID
        }
        throw SteamPathError.noRecentUser
    }

    func cacheURL(steamID: String) -> URL {
        Self.appSupportDir.appendingPathComponent(steamID, isDirectory: true)
    }

    func gamesListCacheURL(steamID: String) -> URL {
        cacheURL(steamID: steamID).appendingPathComponent("games_list.json")
    }

    func profileCacheURL(steamID: String) -> URL {
        cacheURL(steamID: steamID).appendingPathComponent("profile.json")
    }

    private struct VDFUser {
        let steamID: String
        let mostRecent: Bool
    }

    private func parseVDFUsers(_ contents: String) -> [VDFUser] {
        var users: [VDFUser] = []
        var currentID: String?
        var mostRecent = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\"") && line.hasSuffix("\"") && !line.contains("\t") {
                let id = String(line.dropFirst().dropLast())
                if id.allSatisfy(\.isNumber), id.count >= 16 {
                    if let currentID {
                        users.append(VDFUser(steamID: currentID, mostRecent: mostRecent))
                    }
                    currentID = id
                    mostRecent = false
                }
            } else if line.contains("MostRecent") && line.contains("1") {
                mostRecent = true
            }
        }

        if let currentID {
            users.append(VDFUser(steamID: currentID, mostRecent: mostRecent))
        }

        return users
    }
}
