import Foundation

struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let durationSeconds: Double
}

enum AgentShellExecutor {
    private static let blockedEnvironmentPrefixes = ["DYLD_", "LD_"]

    static func execute(
        command: String,
        workingDirectory: String?,
        timeout: TimeInterval = 120,
        maxOutputBytes: Int = 102_400,
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        return try await execute(
            process: process,
            workingDirectory: workingDirectory,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            environment: environment
        )
    }

    static func executeProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectory: String?,
        timeout: TimeInterval = 120,
        maxOutputBytes: Int = 102_400,
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        return try await execute(
            process: process,
            workingDirectory: workingDirectory,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            environment: environment
        )
    }

    private static func execute(
        process: Process,
        workingDirectory: String?,
        timeout: TimeInterval,
        maxOutputBytes: Int,
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        let startTime = Date()

        if let cwd = workingDirectory {
            let cwdURL = URL(fileURLWithPath: cwd)
            if FileManager.default.fileExists(atPath: cwdURL.path) {
                process.currentDirectoryURL = cwdURL
            }
        }

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let currentPath = env["PATH"] ?? ""
        let pathComponents = currentPath.split(separator: ":").map(String.init)
        let missingPaths = extraPaths.filter { !pathComponents.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        if let environment {
            for (key, value) in environment {
                if blockedEnvironmentPrefixes.contains(where: { key.hasPrefix($0) }) {
                    continue
                }
                if key == "PATH" {
                    let basePath = env["PATH"] ?? ""
                    env["PATH"] = [value, basePath]
                        .filter { !$0.isEmpty }
                        .joined(separator: ":")
                } else {
                    env[key] = value
                }
            }
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
