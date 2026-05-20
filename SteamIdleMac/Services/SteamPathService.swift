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

    /// Minimal VDF parser tuned for `loginusers.vdf`. Tracks brace depth so we only
    /// treat keys at the user-object level (depth 2) as SteamIDs, and reads
    /// `"MostRecent" "1"` as a value pair rather than relying on substring heuristics.
    private func parseVDFUsers(_ contents: String) -> [VDFUser] {
        var users: [VDFUser] = []
        var depth = 0
        var currentID: String?
        var mostRecent = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "{" {
                depth += 1
                continue
            }
            if line == "}" {
                if depth == 2, let id = currentID {
                    users.append(VDFUser(steamID: id, mostRecent: mostRecent))
                    currentID = nil
                    mostRecent = false
                }
                depth = max(0, depth - 1)
                continue
            }

            let tokens = vdfTokens(in: line)
            switch tokens.count {
            case 1 where depth == 1:
                // The user block key — a SteamID64. Next non-empty line should be `{`.
                let id = tokens[0]
                if id.allSatisfy(\.isNumber), id.count >= 16 {
                    currentID = id
                    mostRecent = false
                }
            case 2 where depth == 2:
                if tokens[0].caseInsensitiveCompare("MostRecent") == .orderedSame,
                   tokens[1] == "1" {
                    mostRecent = true
                }
            default:
                break
            }
        }

        return users
    }

    /// Splits a VDF line into its quoted tokens. Both keys and values in `loginusers.vdf`
    /// are quoted, so we just collect everything inside matched pairs of `"`.
    private func vdfTokens(in line: String) -> [String] {
        var tokens: [String] = []
        var current: String?
        for char in line {
            if char == "\"" {
                if let value = current {
                    tokens.append(value)
                    current = nil
                } else {
                    current = ""
                }
            } else if current != nil {
                current?.append(char)
            }
        }
        return tokens
    }
}
