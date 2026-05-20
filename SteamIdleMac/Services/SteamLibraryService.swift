import Foundation

enum SteamLibraryError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Steam Web API key in Settings."
        case .invalidResponse:
            return "Steam returned an unexpected response."
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
    private let pathService = SteamPathService()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchOwnedGames(steamID: String, apiKey: String, forceRefresh: Bool = false) async throws -> [Game] {
        if !forceRefresh, let cached = loadCache(steamID: steamID), !cached.isEmpty {
            return cached
        }

        var components = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "include_appinfo", value: "true"),
            URLQueryItem(name: "include_played_free_games", value: "true"),
            URLQueryItem(name: "include_free_sub", value: "true"),
            URLQueryItem(name: "skip_unvetted_apps", value: "false"),
        ]

        guard let url = components.url else {
            throw SteamLibraryError.invalidResponse
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SteamLibraryError.network(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SteamLibraryError.invalidResponse
        }

        let games = try parseGames(from: data)
        try saveCache(games: games, steamID: steamID)
        return games
    }

    func loadCache(steamID: String) -> [Game]? {
        let url = pathService.gamesListCacheURL(steamID: steamID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cache = try? JSONDecoder().decode(GamesListCache.self, from: data) else { return nil }
        return cache.gamesList
    }

    func fetchProfile(steamID: String, apiKey: String, forceRefresh: Bool = false) async throws -> SteamProfile {
        if !forceRefresh, let cached = loadProfileCache(steamID: steamID) {
            return cached
        }

        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamids", value: steamID),
        ]

        guard let url = components.url else {
            throw SteamLibraryError.invalidResponse
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SteamLibraryError.network(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SteamLibraryError.invalidResponse
        }

        let profile = try parseProfile(from: data, steamID: steamID)
        try saveProfileCache(profile: profile, steamID: steamID)
        return profile
    }

    func loadProfileCache(steamID: String) -> SteamProfile? {
        let url = pathService.profileCacheURL(steamID: steamID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamProfile.self, from: data)
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
                let appid = dict["appid"] as? UInt64,
                let name = dict["name"] as? String
            else { continue }

            let playtime = dict["playtime_forever"] as? UInt64 ?? 0
            let iconHash = dict["img_icon_url"] as? String
            let lastPlayed = dict["rtime_last_played"] as? UInt64
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
