import Foundation

/// Centralized constants for URLs that live in multiple views. Computed optionally
/// so we never force-unwrap at call sites.
enum AppLinks {
    static let steamAPIKey: URL? = URL(string: "https://steamcommunity.com/dev/apikey")
}
