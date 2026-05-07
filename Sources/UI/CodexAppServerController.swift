import Foundation

@MainActor
final class CodexAppServerController: ObservableObject {
    static let shared = CodexAppServerController()

    enum Status: Equatable {
        case stopped
        case starting
        case running(pid: Int32, listenURL: String)
        case stopping
        case failed(String)
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastOutputLine: String?
    @Published private(set) var managedProcessCount = 0

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutLineBuffer = Data()
    private var stderrLineBuffer = Data()
    private var stderrTail = Data()
    private var requestedStop = false
    private var refreshTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var shutdownGeneration = 0

    private let stderrTailLimitBytes = 32 * 1024

    private init() {
        refreshManagedProcesses()
    }

    var hasManagedProcesses: Bool {
        managedProcessCount > 0 || process?.isRunning == true
    }

    func start(listenURL rawListenURL: String) throws {
        let listenURL = rawListenURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !listenURL.isEmpty else {
            throw CodexAppServerControlError.invalidListenURL("Listen URL is empty.")
        }

        guard let parsed = URL(string: listenURL),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            throw CodexAppServerControlError.invalidListenURL("Listen URL must use ws:// or wss://.")
        }

        guard process?.isRunning != true else {
            throw CodexAppServerControlError.alreadyRunning
        }
        guard shutdownTask == nil else {
            throw CodexAppServerControlError.launchFailed("Codex app-server is still stopping.")
        }

        teardownProcessResources()
        requestedStop = false
        lastOutputLine = nil
        stdoutLineBuffer.removeAll(keepingCapacity: true)
        stderrLineBuffer.removeAll(keepingCapacity: true)
        stderrTail.removeAll(keepingCapacity: true)
        status = .starting

        var environment = CodexAppServerLaunchSupport.mergedEnvironment()
        environment[CodexManagedProcessSupport.managedEnvironmentKey] = CodexManagedProcessSupport.managedEnvironmentValue
        environment["JIN_MANAGED_CODEX_PARENT_PID"] = String(getpid())
        environment["JIN_MANAGED_CODEX_LISTEN_URL"] = listenURL

        guard let codexExecutable = CodexAppServerLaunchSupport.resolveCodexExecutable(environment: environment) else {
            let hintPath = environment["PATH"] ?? "(empty)"
            let message = "Unable to find `codex` executable. PATH used by app: \(hintPath)"
            status = .failed(message)
            throw CodexAppServerControlError.executableNotFound(message)
        }

        let process = Process()
        process.executableURL = codexExecutable
        process.arguments = ["app-server", "--listen", listenURL]
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeStderr(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleProcessTermination(exitStatus: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            teardownReadHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            status = .failed("Failed to start codex app-server: \(error.localizedDescription)")
            throw CodexAppServerControlError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        managedProcessCount = 1
        status = .running(pid: process.processIdentifier, listenURL: listenURL)
    }

    func stop() {
        beginAsyncShutdown(includeDetectedRemainders: false, force: false)
    }

    func forceStopManagedServers() {
        beginAsyncShutdown(includeDetectedRemainders: true, force: true)
    }

    func shutdownForApplicationTermination() {
        let trackedPID = detachTrackedProcessIfNeeded()
        let outcome = CodexAppServerShutdownSupport.performShutdown(
            trackedPID: trackedPID,
            includeDetectedRemainders: true,
            force: true
        )
        managedProcessCount = outcome.managedProcessCount
        requestedStop = false
    }

    func refreshManagedProcesses() {
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .utility) {
            let count = CodexManagedProcessSupport.managedRootPIDs(
                in: CodexManagedProcessSupport.currentProcessSnapshots()
            ).count
            guard !Task.isCancelled else { return }
            await MainActor.run {
                CodexAppServerController.shared.managedProcessCount = count
            }
        }
    }

    private func beginAsyncShutdown(includeDetectedRemainders: Bool, force: Bool) {
        if shutdownTask != nil {
            guard force else { return }
            shutdownTask?.cancel()
            shutdownTask = nil
        }
        requestedStop = true
        status = .stopping
        refreshTask?.cancel()
        let trackedPID = detachTrackedProcessIfNeeded()

        shutdownGeneration += 1
        let expectedGeneration = shutdownGeneration

        shutdownTask = Task.detached(priority: .utility) {
            let outcome = CodexAppServerShutdownSupport.performShutdown(
                trackedPID: trackedPID,
                includeDetectedRemainders: includeDetectedRemainders,
                force: force
            )
            await MainActor.run {
                let controller = CodexAppServerController.shared
                guard controller.shutdownGeneration == expectedGeneration else { return }
                controller.shutdownTask = nil
                controller.managedProcessCount = outcome.managedProcessCount
                controller.requestedStop = false
                if outcome.remainingPIDs.isEmpty {
                    if force {
                        controller.lastOutputLine = "Force-stopped Jin-managed Codex app-server process(es)."
                    }
                    controller.status = .stopped
                } else {
                    controller.status = .failed("Some Jin-managed Codex app-server processes could not be stopped.")
                }
            }
        }
    }

    private func detachTrackedProcessIfNeeded() -> Int32? {
        let pid = process?.isRunning == true ? process?.processIdentifier : nil
        process?.terminationHandler = nil
        teardownProcessResources()
        return pid
    }

    nonisolated static func shutdownRootPIDs(
        trackedPID: Int32?,
        includeDetectedRemainders: Bool,
        snapshots: [CodexManagedProcessSnapshot]
    ) -> Set<Int32> {
        CodexAppServerShutdownSupport.shutdownRootPIDs(
            trackedPID: trackedPID,
            includeDetectedRemainders: includeDetectedRemainders,
            snapshots: snapshots
        )
    }

    private func handleProcessTermination(exitStatus: Int32) {
        teardownProcessResources()
        defer {
            requestedStop = false
            refreshManagedProcesses()
        }

        if requestedStop || exitStatus == 0 {
            status = .stopped
            return
        }

        status = .failed(bestExitMessage(status: exitStatus))
    }

    private func consumeStdout(_ data: Data) {
        consumeLineData(data, buffer: &stdoutLineBuffer)
    }

    private func consumeStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > stderrTailLimitBytes {
            stderrTail.removeFirst(stderrTail.count - stderrTailLimitBytes)
        }
        consumeLineData(data, buffer: &stderrLineBuffer)
    }

    private func consumeLineData(_ data: Data, buffer: inout Data) {
        buffer.append(data)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty else {
                continue
            }
            lastOutputLine = line
        }

        let maxBufferBytes = 16 * 1024
        if buffer.count > maxBufferBytes {
            buffer.removeFirst(buffer.count - maxBufferBytes)
        }
    }

    private func bestExitMessage(status: Int32) -> String {
        if let lastOutputLine, !lastOutputLine.isEmpty {
            return "codex app-server exited (\(status)): \(lastOutputLine)"
        }

        if let stderrText = String(data: stderrTail, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stderrText.isEmpty {
            return "codex app-server exited (\(status)): \(stderrText)"
        }

        return "codex app-server exited with status \(status)."
    }

    private func teardownReadHandlers(stdoutPipe: Pipe?, stderrPipe: Pipe?) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func teardownProcessResources() {
        process?.terminationHandler = nil
        teardownReadHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
    }
}
