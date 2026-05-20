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
    private var isBatchStartingIdle = false

    init() {
        idleManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                self.idleTimeStore.syncActiveSessions(self.idleManager.activeAppIDs)
                if !self.isBatchStartingIdle {
                    self.scheduleSyncIdleSnapshot()
                }
            }
            .store(in: &cancellables)

        idleTimeStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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

    var topPlaytimeGame: Game? {
        games.max(by: { $0.playtimeForever < $1.playtimeForever })
    }

    var greetingName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Gamer" : trimmed
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
                await refreshProfile(force: false)
            }
        }
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
        } catch {
            if let cached = libraryService.loadCache(steamID: steamID64), !cached.isEmpty {
                games = cached
                errorMessage = "Using cached library: \(error.localizedDescription)"
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

        var failures: [String] = []
        let targetGame = selected.first!

        if !idleManager.activeSessions.isEmpty, !idleManager.activeAppIDs.contains(targetGame.appid) {
            stopAllIdling()
        }
        if !idleManager.activeAppIDs.contains(targetGame.appid), !launchingAppIDs.contains(targetGame.appid) {
            do {
                launchingAppIDs.insert(targetGame.appid)
                try await idleManager.startIdle(game: targetGame)
                selectedAppIDs = [targetGame.appid]
            } catch {
                failures.append("\(targetGame.name): \(error.localizedDescription)")
            }
            launchingAppIDs.remove(targetGame.appid)
        }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        } else if selected.count > 1 {
            errorMessage = "Steam only reports one active game presence at a time. Started \(targetGame.name) only."
        }
    }

    func startIdle(game: Game) {
        if idleManager.activeAppIDs.contains(game.appid) { return }
        if launchingAppIDs.contains(game.appid) { return }
        if !idleManager.activeSessions.isEmpty {
            stopAllIdling()
        }

        Task {
            do {
                launchingAppIDs.insert(game.appid)
                try await idleManager.startIdle(game: game)
                selectedAppIDs.remove(game.appid)
            } catch {
                errorMessage = error.localizedDescription
            }
            launchingAppIDs.remove(game.appid)
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
}
