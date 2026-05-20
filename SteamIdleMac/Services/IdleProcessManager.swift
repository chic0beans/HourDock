import Foundation

enum IdleProcessError: LocalizedError {
    case helperNotFound
    case steamNotRunning
    case maxSessionsReached
    case alreadyIdling
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "idle-helper binary not found. Rebuild the app."
        case .steamNotRunning:
            return "Steam must be running and you must be signed in."
        case .maxSessionsReached:
            return "Steam allows at most 32 games idling at once."
        case .alreadyIdling:
            return "This game is already idling."
        case .failedToStart(let message):
            return message
        }
    }
}

@MainActor
final class IdleProcessManager: ObservableObject {
    static let maxConcurrent = 32
    private static let startReadyTimeoutNs: UInt64 = 5_000_000_000
    private static let postReadyStabilityNs: UInt64 = 120_000_000

    @Published private(set) var activeSessions: [ActiveIdleSession] = []

    private var runningProcesses: [UInt64: Process] = [:]
    private var processRuntimeDirectories: [UInt64: URL] = [:]
    private var startingAppIDs: Set<UInt64> = []
    private let steamRunning = SteamRunningService()
    private let pathService = SteamPathService()

    var activeAppIDs: Set<UInt64> {
        Set(activeSessions.map(\.appid))
    }

    func helperURL() -> URL? {
        if let bundled = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("idle-helper"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let aux = Bundle.main.url(forAuxiliaryExecutable: "idle-helper"),
           FileManager.default.isExecutableFile(atPath: aux.path) {
            return aux
        }

        #if DEBUG
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let devPath = URL(fileURLWithPath: srcRoot)
                .appendingPathComponent("idle-helper/target/release/idle-helper")
            if FileManager.default.isExecutableFile(atPath: devPath.path) {
                return devPath
            }
        }
        #endif
        return nil
    }

    func startIdle(game: Game) async throws {
        if !steamRunning.isSteamRunning() {
            throw IdleProcessError.steamNotRunning
        }

        // Steam appids are u32 on the helper side; reject values that don't fit.
        guard game.appid <= UInt64(UInt32.max) else {
            throw IdleProcessError.failedToStart("Invalid app id: \(game.appid)")
        }

        if activeSessions.contains(where: { $0.appid == game.appid }) ||
           startingAppIDs.contains(game.appid) {
            throw IdleProcessError.alreadyIdling
        }

        if activeSessions.count + startingAppIDs.count >= Self.maxConcurrent {
            throw IdleProcessError.maxSessionsReached
        }

        guard let helper = helperURL() else {
            throw IdleProcessError.helperNotFound
        }

        startingAppIDs.insert(game.appid)
        defer { startingAppIDs.remove(game.appid) }

        // File I/O for the per-helper runtime directory runs off the main actor so the
        // UI stays responsive even on a slow disk.
        let helperDir = helper.deletingLastPathComponent()
        let pathService = self.pathService
        let prepAppID = game.appid
        let runtimeDir = try await Task.detached(priority: .userInitiated) {
            try IdleProcessManager.prepareHelperRuntime(helperDirectory: helperDir,
                                                       appid: prepAppID,
                                                       pathService: pathService)
        }.value
        let environment = try IdleProcessManager.helperEnvironment(helperDirectory: runtimeDir,
                                                                   pathService: pathService)

        let process = Process()
        process.executableURL = helper
        process.arguments = ["idle", String(game.appid), game.name]
        process.currentDirectoryURL = runtimeDir
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        do {
            try await waitForReadySignal(
                process: process,
                stdout: stdoutPipe,
                stderr: stderrPipe
            )
        } catch {
            if process.isRunning { process.terminate() }
            cleanupRuntimeDirectory(for: game.appid, fallback: runtimeDir)
            throw error
        }

        // Re-check capacity after the await; another start may have completed concurrently.
        if activeSessions.count >= Self.maxConcurrent {
            if process.isRunning { process.terminate() }
            cleanupRuntimeDirectory(for: game.appid, fallback: runtimeDir)
            throw IdleProcessError.maxSessionsReached
        }
        if activeSessions.contains(where: { $0.appid == game.appid }) {
            if process.isRunning { process.terminate() }
            cleanupRuntimeDirectory(for: game.appid, fallback: runtimeDir)
            throw IdleProcessError.alreadyIdling
        }

        let appid = game.appid
        let pid = process.processIdentifier
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleUnexpectedTermination(appid: appid, pid: pid)
            }
        }
        runningProcesses[game.appid] = process
        processRuntimeDirectories[game.appid] = runtimeDir
        activeSessions.append(ActiveIdleSession(appid: game.appid, name: game.name, pid: process.processIdentifier))
    }

    func stopIdle(appid: UInt64) {
        guard let process = runningProcesses[appid] else {
            // No tracked Process; treat as already stopped. Don't kill stale PIDs.
            processRuntimeDirectories.removeValue(forKey: appid)
            activeSessions.removeAll { $0.appid == appid }
            return
        }

        // Keep the session in `activeSessions` until termination so widgets/UI stay accurate
        // during the brief teardown window. The handler cleans up state.
        let runtimeDir = processRuntimeDirectories[appid]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.finalizeStop(appid: appid, runtimeDir: runtimeDir)
            }
        }
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak process] in
                if let p = process, p.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        } else {
            finalizeStop(appid: appid, runtimeDir: runtimeDir)
        }
    }

    private func finalizeStop(appid: UInt64, runtimeDir: URL?) {
        runningProcesses.removeValue(forKey: appid)
        processRuntimeDirectories.removeValue(forKey: appid)
        activeSessions.removeAll { $0.appid == appid }
        if let runtimeDir {
            try? FileManager.default.removeItem(at: runtimeDir)
        }
    }

    private func cleanupRuntimeDirectory(for appid: UInt64, fallback: URL) {
        let url = processRuntimeDirectories.removeValue(forKey: appid) ?? fallback
        try? FileManager.default.removeItem(at: url)
    }

    func stopAll() {
        let appids = activeSessions.map(\.appid)
        for appid in appids {
            stopIdle(appid: appid)
        }
    }

    func cleanupOnQuit() {
        stopAll()
    }

    private func handleUnexpectedTermination(appid: UInt64, pid: Int32) {
        guard let tracked = runningProcesses[appid], tracked.processIdentifier == pid else { return }
        let runtimeDir = processRuntimeDirectories[appid]
        runningProcesses.removeValue(forKey: appid)
        processRuntimeDirectories.removeValue(forKey: appid)
        activeSessions.removeAll { $0.appid == appid }
        if let runtimeDir {
            try? FileManager.default.removeItem(at: runtimeDir)
        }
    }

    private func waitForReadySignal(process: Process, stdout: Pipe, stderr: Pipe) async throws {
        let state = HelperOutputState()
        let outBuffer = LineBuffer { line in
            state.record(line: line, fromStdErr: false)
        }
        let errBuffer = LineBuffer { line in
            state.record(line: line, fromStdErr: true)
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF on the pipe: flush whatever's left and detach.
                outBuffer.flush()
                handle.readabilityHandler = nil
            } else {
                outBuffer.append(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errBuffer.flush()
                handle.readabilityHandler = nil
            } else {
                errBuffer.append(data)
            }
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        var elapsed: UInt64 = 0
        let pollStep: UInt64 = 20_000_000

        while elapsed < Self.startReadyTimeoutNs {
            if let reported = state.reportedError {
                throw IdleProcessError.failedToStart(reported)
            }

            if state.hasSuccess {
                // Keep this tiny so "Idle" feels instant while still avoiding immediate races.
                try await Task.sleep(nanoseconds: Self.postReadyStabilityNs)
                if process.isRunning {
                    return
                }
                throw IdleProcessError.failedToStart(state.reportedError ?? parseHelperError(state.joinedOutput))
            }

            if !process.isRunning {
                throw IdleProcessError.failedToStart(state.reportedError ?? parseHelperError(state.joinedOutput))
            }

            try await Task.sleep(nanoseconds: pollStep)
            elapsed += pollStep
        }

        if process.isRunning {
            process.terminate()
        }
        if let reported = state.reportedError {
            throw IdleProcessError.failedToStart(reported)
        }
        let joined = state.joinedOutput
        throw IdleProcessError.failedToStart(joined.isEmpty
            ? "Steam API didn't confirm within 5s. Make sure Steam is running and signed in."
            : parseHelperError(joined))
    }

    private final class LineBuffer: @unchecked Sendable {
        private var buffer = Data()
        private let emit: (String) -> Void
        private let lock = NSLock()

        init(emit: @escaping (String) -> Void) {
            self.emit = emit
        }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                if let line = String(data: lineData, encoding: .utf8) {
                    emit(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                buffer.removeSubrange(0...newlineIndex)
            }
        }

        func flush() {
            lock.lock()
            defer { lock.unlock() }
            guard !buffer.isEmpty else { return }
            if let line = String(data: buffer, encoding: .utf8) {
                emit(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            buffer.removeAll()
        }
    }

    private struct HelperMessage: Decodable {
        let success: String?
        let error: String?
    }

    private final class HelperOutputState: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private var sawSuccess = false
        private var helperError: String?
        private let decoder = JSONDecoder()

        func record(line: String, fromStdErr: Bool) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            lines.append(cleaned)

            // Parse only well-formed NDJSON objects emitted by idle-helper.
            if let data = cleaned.data(using: .utf8),
               let msg = try? decoder.decode(HelperMessage.self, from: data) {
                if !fromStdErr, msg.success != nil {
                    sawSuccess = true
                }
                if let err = msg.error, helperError == nil {
                    helperError = err
                }
            }
        }

        var joinedOutput: String {
            lock.lock()
            defer { lock.unlock() }
            return lines.joined(separator: "\n")
        }

        var hasSuccess: Bool {
            lock.lock()
            defer { lock.unlock() }
            return sawSuccess
        }

        var reportedError: String? {
            lock.lock()
            defer { lock.unlock() }
            return helperError
        }
    }

    // MARK: - Filesystem helpers (Sendable, callable off the main actor)

    nonisolated private static func prepareHelperRuntime(helperDirectory: URL,
                                                         appid: UInt64,
                                                         pathService: SteamPathService) throws -> URL {
        let fm = FileManager.default
        let runtimeDir = helperDirectory.appendingPathComponent("runtime-\(appid)", isDirectory: true)
        try fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let appidFile = runtimeDir.appendingPathComponent("steam_appid.txt")
        try String(appid).write(to: appidFile, atomically: true, encoding: .utf8)

        let bundledDylib = runtimeDir.appendingPathComponent("libsteam_api.dylib")
        if !fm.fileExists(atPath: bundledDylib.path) {
            var candidates: [URL] = [helperDirectory.appendingPathComponent("libsteam_api.dylib")]
            if let frameworksDylib = Bundle.main.privateFrameworksURL?.appendingPathComponent("libsteam_api.dylib") {
                candidates.append(frameworksDylib)
            }
            #if DEBUG
            if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
                let root = URL(fileURLWithPath: srcRoot)
                candidates.append(root.appendingPathComponent("ThirdParty/libsteam_api.dylib"))
                // Search any cargo build directory for a recent libsteam_api.dylib.
                let buildDir = root.appendingPathComponent("idle-helper/target/release/build")
                if let subdirs = try? fm.contentsOfDirectory(at: buildDir, includingPropertiesForKeys: nil) {
                    for sub in subdirs {
                        candidates.append(sub.appendingPathComponent("out/libsteam_api.dylib"))
                    }
                }
            }
            #endif
            if let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
                try? fm.copyItem(at: source, to: bundledDylib)
            }
        }

        let steamClient = try pathService.steamClientLibraryPath().appendingPathComponent("steamclient.dylib")
        let destClient = runtimeDir.appendingPathComponent("steamclient.dylib")
        if fm.fileExists(atPath: steamClient.path) {
            if !fm.fileExists(atPath: destClient.path) {
                try? fm.copyItem(at: steamClient, to: destClient)
            }
        }
        return runtimeDir
    }

    nonisolated private static func helperEnvironment(helperDirectory: URL,
                                                      pathService: SteamPathService) throws -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var paths = [helperDirectory.path]

        if let steamLib = try? pathService.steamClientLibraryPath().path {
            paths.append(steamLib)
        }

        let combined = paths.joined(separator: ":")
        if let existing = env["DYLD_LIBRARY_PATH"], !existing.isEmpty {
            env["DYLD_LIBRARY_PATH"] = combined + ":" + existing
        } else {
            env["DYLD_LIBRARY_PATH"] = combined
        }

        env.removeValue(forKey: "SteamAppId")
        return env
    }

    private func parseHelperError(_ output: String) -> String {
        if output.contains("Steam client must be running") || output.contains("NoSteamClient") {
            return "Steam must be running and you must be signed in."
        }
        if output.contains("Failed to initialize Steam API") || output.contains("steamclient") {
            return "Steam API failed to initialize. Quit and reopen Steam, then try again."
        }
        if output.isEmpty {
            return "idle-helper crashed on startup. Ensure Steam is running."
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
