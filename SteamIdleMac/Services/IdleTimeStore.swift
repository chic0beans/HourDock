import Combine
import Foundation

/// Persists cumulative idle hours per Steam appid.
@MainActor
final class IdleTimeStore: ObservableObject {
    static let shared = IdleTimeStore()

    @Published private(set) var hoursByAppID: [UInt64: Double] = [:]

    private var sessionStartByAppID: [UInt64: Date] = [:]
    private var persistTimer: Timer?
    private let defaultsKey = "idleHoursByAppID"

    private init() {
        load()
    }

    func hours(for appid: UInt64) -> Double {
        storedHours(for: appid) + activeSessionHours(for: appid)
    }

    func formattedHours(for appid: UInt64) -> String {
        let h = hours(for: appid)
        if h < 0.05 { return "" }
        if h < 10 {
            return String(format: "%.1f hours idled", h)
        }
        return String(format: "%.0f hours idled", h)
    }

    func beginTracking(appid: UInt64) {
        guard sessionStartByAppID[appid] == nil else { return }
        sessionStartByAppID[appid] = Date()
        startPersistTimerIfNeeded()
        objectWillChange.send()
    }

    func endTracking(appid: UInt64) {
        guard let start = sessionStartByAppID.removeValue(forKey: appid) else { return }
        let elapsed = Date().timeIntervalSince(start) / 3600.0
        if elapsed > 0 {
            hoursByAppID[appid, default: 0] += elapsed
            persist()
        }
        stopPersistTimerIfIdle()
        objectWillChange.send()
    }

    func endAllTracking() {
        let appids = Array(sessionStartByAppID.keys)
        for appid in appids {
            endTracking(appid: appid)
        }
    }

    func syncActiveSessions(_ appids: Set<UInt64>) {
        let toEnd = Set(sessionStartByAppID.keys).subtracting(appids)
        for appid in toEnd {
            endTracking(appid: appid)
        }
        for appid in appids where sessionStartByAppID[appid] == nil {
            beginTracking(appid: appid)
        }
    }

    private func storedHours(for appid: UInt64) -> Double {
        hoursByAppID[appid] ?? 0
    }

    private func activeSessionHours(for appid: UInt64) -> Double {
        guard let start = sessionStartByAppID[appid] else { return 0 }
        return Date().timeIntervalSince(start) / 3600.0
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return
        }
        hoursByAppID = decoded.reduce(into: [:]) { result, pair in
            if let appid = UInt64(pair.key) {
                result[appid] = pair.value
            }
        }
    }

    private func persist() {
        let encoded = hoursByAppID.reduce(into: [String: Double]()) { $0[String($1.key)] = $1.value }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func startPersistTimerIfNeeded() {
        guard persistTimer == nil else { return }
        persistTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    private func stopPersistTimerIfIdle() {
        guard sessionStartByAppID.isEmpty else { return }
        persistTimer?.invalidate()
        persistTimer = nil
        persist()
    }
}
