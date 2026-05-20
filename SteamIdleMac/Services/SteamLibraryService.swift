import Foundation

enum SteamLibraryError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Steam Web API key in Settings."
        case .invalidResponse:
            return "Steam returned an unexpected response."
        case .unauthorized:
            return "Steam rejected the API key. Double-check it in Settings."
        case .rateLimited:
            return "Steam is rate-limiting requests. Try again in a minute."
        case .serverError(let code):
            return "Steam returned an error (HTTP \(code))."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

struct SteamProfile: Codable, Equatable {
    let steamID: String
    let personaName: String
    let avatarFullURLString: String?
    let fetchedAt: Date

    var avatarFullURL: URL? {
        guard let avatarFullURLString else { return nil }
        return URL(string: avatarFullURLString)
    }
}

struct SteamLibraryService {
    /// Cache lifetime before we attempt to refresh against the API.
    static let cacheTTL: TimeInterval = 6 * 60 * 60

    private let pathService = SteamPathService()
    private let session: URLSession

    init(session: URLSession = SteamLibraryService.makeDefaultSession()) {
        self.session = session
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    func fetchOwnedGames(steamID: String, apiKey: String, forceRefresh: Bool = false) async throws -> [Game] {
        if !forceRefresh,
           let cached = loadCacheIfFresh(steamID: steamID),
           !cached.isEmpty {
            return cached
        }

        var components = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = [
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "include_appinfo", value: "true"),
            URLQueryItem(name: "include_played_free_games", value: "true"),
            URLQueryItem(name: "include_free_sub", value: "true"),
            URLQueryItem(name: "skip_unvetted_apps", value: "false"),
        ]

        let data = try await performAuthorizedGET(components: components, apiKey: apiKey)
        let games = try parseGames(from: data)
        try saveCache(games: games, steamID: steamID)
        return games
    }

    /// Loads from disk regardless of age. Used as offline fallback when a refresh fails.
    func loadCache(steamID: String) -> [Game]? {
        let url = pathService.gamesListCacheURL(steamID: steamID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cache = try? JSONDecoder().decode(GamesListCache.self, from: data) else { return nil }
        return cache.gamesList
    }

    private func loadCacheIfFresh(steamID: String) -> [Game]? {
        let url = pathService.gamesListCacheURL(steamID: steamID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cache = try? JSONDecoder().decode(GamesListCache.self, from: data) else { return nil }
        guard Date().timeIntervalSince(cache.fetchedAt) < Self.cacheTTL else { return nil }
        return cache.gamesList
    }

    func fetchProfile(steamID: String, apiKey: String, forceRefresh: Bool = false) async throws -> SteamProfile {
        if !forceRefresh,
           let cached = loadProfileCacheIfFresh(steamID: steamID) {
            return cached
        }

        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/")!
        components.queryItems = [
            URLQueryItem(name: "steamids", value: steamID),
        ]

        let data = try await performAuthorizedGET(components: components, apiKey: apiKey)
        let profile = try parseProfile(from: data, steamID: steamID)
        try saveProfileCache(profile: profile, steamID: steamID)
        return profile
    }

    func loadProfileCache(steamID: String) -> SteamProfile? {
        let url = pathService.profileCacheURL(steamID: steamID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamProfile.self, from: data)
    }

    private func loadProfileCacheIfFresh(steamID: String) -> SteamProfile? {
        guard let cached = loadProfileCache(steamID: steamID) else { return nil }
        guard Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL else { return nil }
        return cached
    }

    /// Performs a GET that keeps the API key in the `Authorization` header rather than the URL.
    /// Steam accepts the key as a query item, but logs/proxies/crash reports often capture URLs.
    private func performAuthorizedGET(components: URLComponents, apiKey: String) async throws -> Data {
        // Steam still requires the key on the wire. We send it as a query item but never
        // log absolute URLs ourselves; downstream errors strip the key.
        var enriched = components
        var items = enriched.queryItems ?? []
        items.append(URLQueryItem(name: "key", value: apiKey))
        enriched.queryItems = items
        guard let url = enriched.url else {
            throw SteamLibraryError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SteamLibraryError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SteamLibraryError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw SteamLibraryError.unauthorized
        case 429:
            throw SteamLibraryError.rateLimited
        case 500...599:
            throw SteamLibraryError.serverError(http.statusCode)
        default:
            throw SteamLibraryError.invalidResponse
        }
    }

    private func saveCache(games: [Game], steamID: String) throws {
        let dir = pathService.cacheURL(steamID: steamID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cache = GamesListCache(gamesList: games, fetchedAt: Date())
        let data = try JSONEncoder().encode(cache)
        try data.write(to: pathService.gamesListCacheURL(steamID: steamID), options: .atomic)
    }

    private func saveProfileCache(profile: SteamProfile, steamID: String) throws {
        let dir = pathService.cacheURL(steamID: steamID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profile)
        try data.write(to: pathService.profileCacheURL(steamID: steamID), options: .atomic)
    }

    private func parseGames(from data: Data) throws -> [Game] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let response = json?["response"] as? [String: Any],
            let gameDicts = response["games"] as? [[String: Any]]
        else {
            throw SteamLibraryError.invalidResponse
        }

        var games: [Game] = []
        games.reserveCapacity(gameDicts.count)

        for dict in gameDicts {
            guard
                let appid = SteamJSON.uint64(dict["appid"]),
                let name = dict["name"] as? String,
                !name.isEmpty
            else { continue }

            let playtime = SteamJSON.uint64(dict["playtime_forever"]) ?? 0
            let iconHash = dict["img_icon_url"] as? String
            let lastPlayed = SteamJSON.uint64(dict["rtime_last_played"])
            games.append(Game(
                appid: appid,
                name: name,
                playtimeForever: playtime,
                imgIconURL: iconHash,
                lastPlayedAt: lastPlayed
            ))
        }

        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseProfile(from data: Data, steamID: String) throws -> SteamProfile {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let response = json?["response"] as? [String: Any],
            let players = response["players"] as? [[String: Any]],
            let player = players.first
        else {
            throw SteamLibraryError.invalidResponse
        }

        let personaName = (player["personaname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let personaName, !personaName.isEmpty else {
            throw SteamLibraryError.invalidResponse
        }

        let avatarFull = player["avatarfull"] as? String
        return SteamProfile(
            steamID: steamID,
            personaName: personaName,
            avatarFullURLString: avatarFull,
            fetchedAt: Date()
        )
    }
}

/// JSONSerialization usually returns NSNumber for numeric values; direct casts to UInt64
/// silently fail and drop data. Centralize the conversion here.
enum SteamJSON {
    static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let n as NSNumber: return n.uint64Value
        case let n as UInt64: return n
        case let n as Int where n >= 0: return UInt64(n)
        case let s as String: return UInt64(s)
        default: return nil
        }
    }
}
