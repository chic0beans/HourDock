import Combine
import Foundation
import SwiftUI
import WidgetKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case apiKey = 1
    case stylePicker = 2
}

@MainActor
final class AppState: ObservableObject {
    @Published var games: [Game] = []
    @Published var selectedAppIDs: Set<UInt64> = []
    @Published var searchText = ""
    @Published var sortOrder: GameSortOrder = .name
    @Published var steamID64 = ""
    @Published var apiKey = ""
    @Published var isLoadingLibrary = false
    @Published var isLoadingProfile = false
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published private(set) var launchingAppIDs: Set<UInt64> = []
    @Published var profileName: String = "Gamer"
    @Published var profileAvatarURL: URL?

    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false
    @AppStorage("bannerStyle") private var bannerStyleRaw: String = BannerStyle.landscape.rawValue
    @AppStorage("sortAscending") var sortAscending: Bool = false

    var bannerStyle: BannerStyle {
        get { BannerStyle(rawValue: bannerStyleRaw) ?? .landscape }
        set { bannerStyleRaw = newValue.rawValue }
    }

    let idleManager = IdleProcessManager()
    let idleTimeStore = IdleTimeStore.shared

    private let pathService = SteamPathService()
    private let libraryService = SteamLibraryService()
    private var cancellables = Set<AnyCancellable>()
    private var snapshotSyncTask: Task<Void, Never>?
    private var artworkWarmupTask: Task<Void, Never>?
    private var isBatchStartingIdle = false
    private var lastProfileNetworkRefresh: Date?
    private let greetingPrefix: String

    init() {
        greetingPrefix = GreetingPhrases.all.randomElement() ?? "Hello"
        idleManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                self.objectWillChange.send()
                self.idleTimeStore.syncActiveSessions(Set(sessions.map(\.appid)))
                if !self.isBatchStartingIdle {
                    self.scheduleSyncIdleSnapshot()
                }
            }
            .store(in: &cancellables)

        // Intentionally do NOT forward idleTimeStore.objectWillChange here. The store
        // ticks every 60 seconds, and re-publishing AppState would re-body the whole
        // library. Views that show hours observe the store directly.
        idleTimeStore.syncActiveSessions(idleManager.activeAppIDs)
        syncIdleSnapshot()
    }

    var filteredGames: [Game] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [Game]
        if query.isEmpty {
            base = games
        } else {
            base = games.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return sortOrder.sort(base, ascending: sortAscending)
    }

    var canStartIdle: Bool {
        !selectedAppIDs.isEmpty &&
        idleManager.activeSessions.count < IdleProcessManager.maxConcurrent &&
        launchingAppIDs.isEmpty
    }

    var greetingName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Gamer" : trimmed
    }

    var greetingLine: String {
        "\(greetingPrefix), \(greetingName)"
    }

    func toggleSortDirection() {
        sortAscending.toggle()
    }

    func bootstrap() {
        apiKey = KeychainService.loadAPIKey() ?? ""
        do {
            steamID64 = try pathService.detectSteamID64()
        } catch {
            errorMessage = error.localizedDescription
        }

        if !steamID64.isEmpty {
            loadProfileFromCache()
        }

        if onboardingCompleted, !apiKey.isEmpty, !steamID64.isEmpty {
            Task {
                await refreshLibrary(force: false)
                // Always hit the network on launch so name/avatar match Steam after profile edits.
                await refreshProfileFromNetwork(minInterval: 0)
            }
        }
    }

    /// Fetches the latest Steam persona name and avatar. Use on launch and when the app
    /// becomes active; `minInterval` skips redundant calls if we refreshed recently.
    func refreshProfileFromNetwork(minInterval: TimeInterval = 30) async {
        if let last = lastProfileNetworkRefresh,
           Date().timeIntervalSince(last) < minInterval {
            return
        }
        await refreshProfile(force: true)
        lastProfileNetworkRefresh = Date()
    }

    func saveSettings() throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            try KeychainService.deleteAPIKey()
            return
        }
        try KeychainService.saveAPIKey(trimmedKey)
    }

    func completeOnboarding() {
        onboardingCompleted = true
    }

    func resetOnboarding() {
        onboardingCompleted = false
    }

    func openSettingsWindow() {
        showSettings = true
    }

    func detectSteamIDFromActiveAccount() {
        do {
            steamID64 = try pathService.detectSteamID64()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshLibrary(force: Bool) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = SteamLibraryError.missingAPIKey.localizedDescription
            return
        }

        if steamID64.isEmpty {
            do {
                steamID64 = try pathService.detectSteamID64()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        isLoadingLibrary = true
        errorMessage = nil
        defer { isLoadingLibrary = false }

        do {
            games = try await libraryService.fetchOwnedGames(
                steamID: steamID64,
                apiKey: key,
                forceRefresh: force
            )
            scheduleArtworkWarmup(force: force)
        } catch {
            if let cached = libraryService.loadCache(steamID: steamID64), !cached.isEmpty {
                games = cached
                errorMessage = "Using cached library: \(error.localizedDescription)"
                scheduleArtworkWarmup(force: false)
            } else {
                errorMessage = error.localizedDescription
            }
        }
        syncIdleSnapshot()
    }

    func refreshProfile(force: Bool) async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !steamID64.isEmpty else { return }

        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            let profile = try await libraryService.fetchProfile(
                steamID: steamID64,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                forceRefresh: force
            )
            profileName = profile.personaName
            profileAvatarURL = profile.avatarFullURL
        } catch {
            if let cached = libraryService.loadProfileCache(steamID: steamID64) {
                profileName = cached.personaName
                profileAvatarURL = cached.avatarFullURL
                if force {
                    errorMessage = "Using cached profile: \(error.localizedDescription)"
                }
            } else if force {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadProfileFromCache() {
        guard !steamID64.isEmpty else { return }
        if let cached = libraryService.loadProfileCache(steamID: steamID64) {
            profileName = cached.personaName
            profileAvatarURL = cached.avatarFullURL
        }
    }

    func toggleSelection(_ game: Game) {
        if selectedAppIDs.contains(game.appid) {
            selectedAppIDs.remove(game.appid)
            return
        }

        if selectedAppIDs.count + idleManager.activeSessions.count >= IdleProcessManager.maxConcurrent {
            errorMessage = IdleProcessError.maxSessionsReached.localizedDescription
            return
        }

        selectedAppIDs.insert(game.appid)
    }

    func startIdleForSelection() {
        Task { await startIdleForSelectionAsync() }
    }

    func startIdleForSelectionAsync() async {
        let selected = games.filter { selectedAppIDs.contains($0.appid) }
        guard !selected.isEmpty else { return }

        isBatchStartingIdle = true
        defer {
            isBatchStartingIdle = false
            syncIdleSnapshot()
        }

        let alreadyActive = idleManager.activeAppIDs
        let candidates = selected.filter { !alreadyActive.contains($0.appid) }
        let capacity = max(0, IdleProcessManager.maxConcurrent - idleManager.activeSessions.count)
        guard capacity > 0 else {
            errorMessage = IdleProcessError.maxSessionsReached.localizedDescription
            return
        }

        var failures: [String] = []
        var started: [UInt64] = []

        for game in candidates.prefix(capacity) {
            if launchingAppIDs.contains(game.appid) { continue }
            _ = withAnimation(.easeInOut(duration: 0.15)) {
                launchingAppIDs.insert(game.appid)
            }
            do {
                try await idleManager.startIdle(game: game)
                started.append(game.appid)
            } catch {
                failures.append("\(game.name): \(error.localizedDescription)")
            }
            _ = withAnimation(.easeInOut(duration: 0.15)) {
                launchingAppIDs.remove(game.appid)
            }
        }

        // Clear selection for everything we just kicked off so the UI shows them in the
        // "Idling" section rather than as still-selected.
        for appid in started {
            selectedAppIDs.remove(appid)
        }
        if candidates.count > capacity {
            failures.append("Reached the \(IdleProcessManager.maxConcurrent)-game limit; \(candidates.count - capacity) skipped.")
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    func startIdle(game: Game) {
        if idleManager.activeAppIDs.contains(game.appid) { return }
        if launchingAppIDs.contains(game.appid) { return }
        if idleManager.activeSessions.count >= IdleProcessManager.maxConcurrent {
            errorMessage = IdleProcessError.maxSessionsReached.localizedDescription
            return
        }

        _ = withAnimation(.easeInOut(duration: 0.15)) {
            launchingAppIDs.insert(game.appid)
        }
        Task {
            do {
                try await idleManager.startIdle(game: game)
                selectedAppIDs.remove(game.appid)
            } catch {
                errorMessage = error.localizedDescription
            }
            _ = withAnimation(.easeInOut(duration: 0.15)) {
                launchingAppIDs.remove(game.appid)
            }
        }
    }

    func stopIdle(game: Game) {
        launchingAppIDs.remove(game.appid)
        idleManager.stopIdle(appid: game.appid)
        idleTimeStore.endTracking(appid: game.appid)
    }

    func stopIdle(appid: UInt64) {
        launchingAppIDs.remove(appid)
        idleManager.stopIdle(appid: appid)
        idleTimeStore.endTracking(appid: appid)
    }

    func stopAllIdling() {
        launchingAppIDs.removeAll()
        idleManager.stopAll()
        idleTimeStore.endAllTracking()
        syncIdleSnapshot()
    }

    private func scheduleSyncIdleSnapshot() {
        snapshotSyncTask?.cancel()
        snapshotSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            syncIdleSnapshot()
        }
    }

    private func syncIdleSnapshot() {
        if idleManager.activeSessions.isEmpty {
            IdleSnapshotStore.clear()
        } else {
            IdleSnapshotStore.save(sessions: idleManager.activeSessions, games: games)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleArtworkWarmup(force: Bool) {
        artworkWarmupTask?.cancel()
        let currentGames = games
        artworkWarmupTask = Task(priority: .utility) { @MainActor in
            // Let profile/library UI paint first, then warm cache in background.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if force {
                RemoteImageCache.shared.clear()
            }
            let urls = currentGames.flatMap { game in
                // Warm small/important assets first to keep profile + menu responsive.
                [game.widgetIconURL, game.iconImageURL, game.headerImageURL].compactMap { $0 }
            }
            await RemoteImageCache.shared.prefetch(Array(urls.prefix(320)))
        }
    }
}
