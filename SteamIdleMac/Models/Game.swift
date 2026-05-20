import Foundation

struct Game: Identifiable, Codable, Hashable {
    let appid: UInt64
    let name: String
    let playtimeForever: UInt64
    let imgIconURL: String?
    let lastPlayedAt: UInt64?

    var id: UInt64 { appid }

    var playtimeHours: Double {
        Double(playtimeForever) / 60.0
    }

    var headerImageURL: URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appid)/header.jpg")!
    }

    var iconImageURL: URL? {
        guard let hash = imgIconURL, !hash.isEmpty else {
            return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appid)/capsule_184x69.jpg")
        }
        return URL(string: "https://media.steampowered.com/steamcommunity/public/images/apps/\(appid)/\(hash).jpg")
    }

    /// Prefer higher-res art for widgets and compact banners (scaled down).
    var widgetIconURL: URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appid)/logo.png")!
    }

    var capsuleImageURL: URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appid)/library_600x900.jpg")!
    }

    init(appid: UInt64, name: String, playtimeForever: UInt64, imgIconURL: String? = nil, lastPlayedAt: UInt64? = nil) {
        self.appid = appid
        self.name = name
        self.playtimeForever = playtimeForever
        self.imgIconURL = imgIconURL
        self.lastPlayedAt = lastPlayedAt
    }

    enum CodingKeys: String, CodingKey {
        case appid
        case name
        case playtimeForever = "playtime_forever"
        case imgIconURL = "img_icon_url"
        case lastPlayedAt = "rtime_last_played"
    }
}

struct GamesListCache: Codable {
    let gamesList: [Game]
    let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case gamesList = "games_list"
        case fetchedAt = "fetched_at"
    }
}

struct ActiveIdleSession: Identifiable, Hashable {
    let appid: UInt64
    let name: String
    let pid: Int32

    var id: UInt64 { appid }
}
