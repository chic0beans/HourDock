import Foundation
import Sparkle
import SwiftUI

/// Wrapper around SPUStandardUpdaterController. We instantiate it lazily so that startup
/// doesn't crash when SUFeedURL/SUPublicEDKey have not been configured yet (e.g. ad-hoc dev builds).
@MainActor
final class SparkleUpdaterController: ObservableObject {
    private var _updater: SPUStandardUpdaterController?

    private var updater: SPUStandardUpdaterController? {
        if _updater == nil, isConfigured {
            _updater = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        return _updater
    }

    var canCheck: Bool {
        guard let u = updater else { return false }
        return u.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updater?.checkForUpdates(nil)
    }

    private var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pub = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Sparkle 2.x will refuse to install updates without an EdDSA public key, so we require
        // both `SUFeedURL` and `SUPublicEDKey` before creating the standard controller. Dev
        // builds without these keys silently disable the "Check for updates..." menu items.
        return !feed.isEmpty && !pub.isEmpty
    }
}
