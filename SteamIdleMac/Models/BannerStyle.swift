import Foundation

enum BannerStyle: String, CaseIterable, Identifiable, Codable {
    case landscape
    case icon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .landscape: return "Banner"
        case .icon: return "Icon"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .landscape: return CGSize(width: 460, height: 248)
        case .icon: return CGSize(width: 88, height: 100)
        }
    }

    var iconArtworkSize: CGFloat {
        switch self {
        case .landscape: return 0
        case .icon: return 56
        }
    }
}
