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
    static let maxConcurrent = 1
    private static let startReadyTimeoutNs: UInt64 = 5_000_000_000
    private static let postReadyStabilityNs: UInt64 = 1_200_000_000

    @Published private(set) var activeSessions: [ActiveIdleSession] = []

    private var runningProcesses: [UInt64: Process] = [:]
    private var processRuntimeDirectories: [UInt64: URL] = [:]
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

        let devPath = URL(fileURLWithPath: "/Users/george/Documents/SteamIdleMac/idle-helper/target/release/idle-helper")
        if FileManager.default.isExecutableFile(atPath: devPath.path) {
            return devPath
        }
        return nil
    }

    func startIdle(game: Game) async throws {
        if !steamRunning.isSteamRunning() {
            throw IdleProcessError.steamNotRunning
        }

        if activeSessions.contains(where: { $0.appid == game.appid }) {
            throw IdleProcessError.alreadyIdling
        }

        if activeSessions.count >= Self.maxConcurrent {
            throw IdleProcessError.maxSessionsReached
        }

        guard let helper = helperURL() else {
            throw IdleProcessError.helperNotFound
        }

        let helperDir = helper.deletingLastPathComponent()
        let runtimeDir = try prepareHelperRuntime(helperDirectory: helperDir, appid: game.appid)

        let process = Process()
        process.executableURL = helper
        process.arguments = ["idle", String(game.appid), game.name]
        process.currentDirectoryURL = runtimeDir
        process.environment = try helperEnvironment(helperDirectory: runtimeDir)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        try await waitForReadySignal(
            process: process,
            stdout: stdoutPipe,
            stderr: stderrPipe
        )

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
        if let process = runningProcesses[appid] {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        } else if let session = activeSessions.first(where: { $0.appid == appid }) {
            kill(session.pid, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                kill(session.pid, SIGKILL)
            }
        }
        runningProcesses.removeValue(forKey: appid)
        processRuntimeDirectories.removeValue(forKey: appid)
        activeSessions.removeAll { $0.appid == appid }
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
        runningProcesses.removeValue(forKey: appid)
        processRuntimeDirectories.removeValue(forKey: appid)
        activeSessions.removeAll { $0.appid == appid }
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
            if data.isEmpty { outBuffer.flush() } else { outBuffer.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { errBuffer.flush() } else { errBuffer.append(data) }
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        var elapsed: UInt64 = 0
        let pollStep: UInt64 = 20_000_000

        while elapsed < Self.startReadyTimeoutNs {
            if state.hasSuccess {
                // Guard against transient startups that print success then drop quickly.
                try await Task.sleep(nanoseconds: Self.postReadyStabilityNs)
                if process.isRunning {
                    return
                }
                throw IdleProcessError.failedToStart(parseHelperError(state.joinedOutput))
            }

            if !process.isRunning {
                throw IdleProcessError.failedToStart(parseHelperError(state.joinedOutput))
            }

            try await Task.sleep(nanoseconds: pollStep)
            elapsed += pollStep
        }

        if process.isRunning {
            process.terminate()
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

    private final class HelperOutputState: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private var sawSuccess = false

        func record(line: String, fromStdErr: Bool) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            lines.append(cleaned)
            if !fromStdErr && (cleaned.contains("\"success\"") || cleaned.contains("Steam API initialized")) {
                sawSuccess = true
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
    }

    private func prepareHelperRuntime(helperDirectory: URL, appid: UInt64) throws -> URL {
        let fm = FileManager.default
        let runtimeDir = helperDirectory.appendingPathComponent("runtime-\(appid)", isDirectory: true)
        try fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let appidFile = runtimeDir.appendingPathComponent("steam_appid.txt")
        try String(appid).write(to: appidFile, atomically: true, encoding: .utf8)

        let bundledDylib = runtimeDir.appendingPathComponent("libsteam_api.dylib")
        if !fm.fileExists(atPath: bundledDylib.path) {
            let candidates = [
                URL(fileURLWithPath: "/Users/george/Documents/SteamIdleMac/ThirdParty/libsteam_api.dylib"),
                helperDirectory.appendingPathComponent("libsteam_api.dylib"),
                URL(fileURLWithPath: "/Users/george/Documents/SteamIdleMac/idle-helper/target/release/build/steamworks-sys-2cb9440c9a5c448e/out/libsteam_api.dylib")
            ]
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

    private func helperEnvironment(helperDirectory: URL) throws -> [String: String] {
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
