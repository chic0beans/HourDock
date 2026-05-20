import Foundation

enum GameSortOrder: String, CaseIterable, Identifiable {
    case name = "Name"
    case playtimeHighest = "Playtime"
    case recentlyPlayed = "Recent"

    var id: String { rawValue }

    var displayLabel: String { rawValue }

    /// Tooltip describing what each direction means for this sort mode.
    func directionHelp(ascending: Bool) -> String {
        switch self {
        case .name:
            return ascending ? "Sort A–Z" : "Sort Z–A"
        case .playtimeHighest:
            return ascending ? "Lowest playtime first" : "Highest playtime first"
        case .recentlyPlayed:
            return ascending ? "Oldest first" : "Most recent first"
        }
    }

    func sort(_ games: [Game], ascending: Bool) -> [Game] {
        switch self {
        case .name:
            return games.sorted {
                let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
                return ascending
                    ? (cmp == .orderedAscending)
                    : (cmp == .orderedDescending)
            }
        case .playtimeHighest:
            return games.sorted {
                ascending
                    ? ($0.playtimeForever < $1.playtimeForever)
                    : ($0.playtimeForever > $1.playtimeForever)
            }
        case .recentlyPlayed:
            return games.sorted {
                let a = $0.lastPlayedAt ?? 0
                let b = $1.lastPlayedAt ?? 0
                return ascending ? (a < b) : (a > b)
            }
        }
    }
}
