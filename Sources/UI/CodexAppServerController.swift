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

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutLineBuffer = Data()
    private var stderrLineBuffer = Data()
    private var stderrTail = Data()
    private var requestedStop = false

    private let stderrTailLimitBytes = 32 * 1024

    private static let defaultPathEntries: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    private init() {}

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

        teardownProcessResources()
        requestedStop = false
        lastOutputLine = nil
        stdoutLineBuffer.removeAll(keepingCapacity: true)
        stderrLineBuffer.removeAll(keepingCapacity: true)
        stderrTail.removeAll(keepingCapacity: true)
        status = .starting

        let environment = mergedEnvironment()
        guard let codexExecutable = resolveCodexExecutable(environment: environment) else {
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
        status = .running(pid: process.processIdentifier, listenURL: listenURL)
    }

    func stop() {
        guard let process, process.isRunning else {
            teardownProcessResources()
            status = .stopped
            return
        }

        requestedStop = true
        status = .stopping
        process.terminate()
    }

    private func handleProcessTermination(exitStatus: Int32) {
        teardownProcessResources()
        defer { requestedStop = false }

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

    private func mergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let pathEntries = existingPath
            .split(separator: ":")
            .map { String($0) }

        var merged = pathEntries
        for entry in Self.defaultPathEntries where !merged.contains(entry) {
            merged.append(entry)
        }
        for entry in commonUserPathEntries() where !merged.contains(entry) {
            merged.append(entry)
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    private func commonUserPathEntries() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.superset/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.claude/bin",
            "\(home)/.opencode/bin",
            "\(home)/.bun/bin",
        ]
    }

    private func resolveCodexExecutable(environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }

        for entry in pathEntries where !entry.isEmpty {
            let path = URL(fileURLWithPath: entry, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func teardownReadHandlers(stdoutPipe: Pipe?, stderrPipe: Pipe?) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func teardownProcessResources() {
        teardownReadHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
    }
}

private enum CodexAppServerControlError: LocalizedError {
    case invalidListenURL(String)
    case alreadyRunning
    case executableNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidListenURL(let message):
            return message
        case .alreadyRunning:
            return "codex app-server is already running."
        case .executableNotFound(let message):
            return message
        case .launchFailed(let message):
            return message
        }
    }
}
