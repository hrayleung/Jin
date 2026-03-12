import Foundation

struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let durationSeconds: Double
}

enum AgentShellExecutor {
    static func execute(
        command: String,
        workingDirectory: String?,
        timeout: TimeInterval = 120,
        maxOutputBytes: Int = 102_400
    ) async throws -> ShellResult {
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let cwd = workingDirectory {
            let cwdURL = URL(fileURLWithPath: cwd)
            if FileManager.default.fileExists(atPath: cwdURL.path) {
                process.currentDirectoryURL = cwdURL
            }
        }

        // Enrich PATH
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let currentPath = env["PATH"] ?? ""
        let pathComponents = currentPath.split(separator: ":").map(String.init)
        let missingPaths = extraPaths.filter { !pathComponents.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutWorkItem = DispatchWorkItem { [weak process] in
                    if let p = process, p.isRunning {
                        p.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + timeout,
                    execute: timeoutWorkItem
                )

                process.terminationHandler = { terminatedProcess in
                    timeoutWorkItem.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = truncateOutput(stdoutData, maxBytes: maxOutputBytes)
                    let stderr = truncateOutput(stderrData, maxBytes: maxOutputBytes)
                    let duration = Date().timeIntervalSince(startTime)

                    continuation.resume(returning: ShellResult(
                        exitCode: terminatedProcess.terminationStatus,
                        stdout: stdout,
                        stderr: stderr,
                        durationSeconds: duration
                    ))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func truncateOutput(_ data: Data, maxBytes: Int) -> String {
        if data.count <= maxBytes {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? "<binary output: \(data.count) bytes>"
        }

        let truncated = data.prefix(maxBytes)
        let text = String(data: truncated, encoding: .utf8)
            ?? String(data: truncated, encoding: .ascii)
            ?? "<binary output: \(data.count) bytes>"
        return text + "\n\n[Output truncated: \(data.count) bytes total, showing first \(maxBytes) bytes]"
    }
}
