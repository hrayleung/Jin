import Foundation

extension RTKRuntimeSupport {
    private static var helperOverrideEnvKey: String { "JIN_RTK_PATH" }

    static func helperExecutableURLIfAvailable() -> URL? {
        if let overrideValue = ProcessInfo.processInfo.environment[helperOverrideEnvKey]?.trimmedNonEmpty {
            let url = URL(fileURLWithPath: overrideValue)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("rtk", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    static func helperExecutableURL() throws -> URL {
        if let overrideValue = ProcessInfo.processInfo.environment[helperOverrideEnvKey]?.trimmedNonEmpty {
            let url = URL(fileURLWithPath: overrideValue)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw RTKRuntimeError.helperMisconfigured(path: overrideValue)
            }
            return url
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("rtk", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: bundled.path) else {
            throw RTKRuntimeError.missingHelper(expectedPath: bundled.path)
        }
        return bundled
    }

    static func versionString() async throws -> String {
        let helperURL = try helperExecutableURL()
        let result = try await AgentShellExecutor.executeProcess(
            executableURL: helperURL,
            arguments: ["--version"],
            workingDirectory: nil,
            timeout: 10,
            maxOutputBytes: 4_096,
            environment: try managedEnvironment(helperURL: helperURL)
        )
        guard result.exitCode == 0 else {
            let details = failureDetails(stdout: result.stdout, stderr: result.stderr)
            throw RTKRuntimeError.versionProbeFailed(exitCode: result.exitCode, details: details)
        }
        guard let output = result.stdout.trimmedNonEmpty else {
            throw RTKRuntimeError.versionProbeFailed(exitCode: result.exitCode, details: "RTK helper returned empty version output.")
        }
        return output
    }
}
