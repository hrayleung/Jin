import Foundation

extension RTKRuntimeSupport {
    private static var teeDirectoryOverrideEnvKey: String { "RTK_TEE_DIR" }

    static func prepareShellCommand(_ command: String) async throws -> String {
        guard let trimmed = command.trimmedNonEmpty else {
            throw RTKRuntimeError.unsupportedCommand(command)
        }

        try RTKConfigManager.ensureManagedConfiguration()
        let helperURL = try helperExecutableURL()
        let result = try await AgentShellExecutor.executeProcess(
            executableURL: helperURL,
            arguments: ["rewrite", trimmed],
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 16_384,
            environment: try managedEnvironment(helperURL: helperURL)
        )

        let rewritten = result.stdout.trimmed
        if result.exitCode == 0 {
            guard !rewritten.isEmpty else {
                throw RTKRuntimeError.invalidRewriteOutput
            }
            return rewritten
        }

        throw RTKRuntimeError.unsupportedCommand(trimmed)
    }

    static func executeRewrittenShellCommand(
        _ rewrittenCommand: String,
        workingDirectory: String?,
        timeout: TimeInterval,
        maxOutputBytes: Int
    ) async throws -> RTKExecutionOutput {
        try RTKConfigManager.ensureManagedConfiguration()
        let helperURL = try helperExecutableURL()
        let shellResult = try await AgentShellExecutor.execute(
            command: rewrittenCommand,
            workingDirectory: workingDirectory,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            environment: try managedEnvironment(helperURL: helperURL)
        )
        let text = combinedOutput(stdout: shellResult.stdout, stderr: shellResult.stderr)
        return RTKExecutionOutput(
            text: text,
            exitCode: shellResult.exitCode,
            durationSeconds: shellResult.durationSeconds,
            rawOutputPath: resolveRawOutputPath(in: text)
        )
    }

    static func executeHelperCommand(
        arguments: [String],
        workingDirectory: String?,
        timeout: TimeInterval,
        maxOutputBytes: Int
    ) async throws -> RTKExecutionOutput {
        try RTKConfigManager.ensureManagedConfiguration()
        let helperURL = try helperExecutableURL()
        let shellResult = try await AgentShellExecutor.executeProcess(
            executableURL: helperURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            environment: try managedEnvironment(helperURL: helperURL)
        )
        let text = combinedOutput(stdout: shellResult.stdout, stderr: shellResult.stderr)
        return RTKExecutionOutput(
            text: text,
            exitCode: shellResult.exitCode,
            durationSeconds: shellResult.durationSeconds,
            rawOutputPath: resolveRawOutputPath(in: text)
        )
    }

    static func managedEnvironment(helperURL: URL) throws -> [String: String] {
        let teeDirectoryURL = try RTKConfigManager.teeDirectoryURL()
        var environment: [String: String] = [
            teeDirectoryOverrideEnvKey: teeDirectoryURL.path
        ]

        if let homeOverride = RTKConfigManager.managedHomeDirectoryPath() {
            environment["HOME"] = homeOverride
        }

        let helperDirectory = helperURL.deletingLastPathComponent().path
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if currentPath.isEmpty {
            environment["PATH"] = helperDirectory
        } else if currentPath.split(separator: ":").map(String.init).contains(helperDirectory) {
            environment["PATH"] = currentPath
        } else {
            environment["PATH"] = helperDirectory + ":" + currentPath
        }

        return environment
    }

    private static func combinedOutput(stdout: String, stderr: String) -> String {
        var output = stdout
        if !stderr.isEmpty {
            if !output.isEmpty {
                output += "\n\n"
            }
            output += "[stderr]\n\(stderr)"
        }
        guard let trimmedOutput = output.trimmedNonEmpty else {
            return "(no output)"
        }
        return trimmedOutput
    }
}
