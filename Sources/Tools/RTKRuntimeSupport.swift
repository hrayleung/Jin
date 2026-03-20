import Foundation

struct RTKRuntimeStatus: Sendable {
    let helperURL: URL?
    let helperVersion: String?
    let configURL: URL
    let teeDirectoryURL: URL
    let errorDescription: String?
}

struct RTKExecutionOutput: Sendable {
    let text: String
    let exitCode: Int32
    let durationSeconds: Double
    let rawOutputPath: String?

    var isError: Bool {
        exitCode != 0
    }
}

enum RTKRuntimeError: LocalizedError {
    case missingHelper(expectedPath: String)
    case helperMisconfigured(path: String)
    case unsupportedCommand(String)
    case invalidRewriteOutput
    case configDirectoryUnavailable
    case configWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingHelper(let expectedPath):
            return "Bundled RTK helper is unavailable at \(expectedPath). Repackage Jin before using Agent shell/search tools."
        case .helperMisconfigured(let path):
            return "RTK helper path is invalid: \(path)"
        case .unsupportedCommand(let command):
            return "RTK cannot rewrite this shell command: \(command). Use dedicated tools like file_read/grep_search/glob_search or switch to an RTK-supported command."
        case .invalidRewriteOutput:
            return "RTK returned an empty rewrite result."
        case .configDirectoryUnavailable:
            return "Unable to locate the RTK configuration directory."
        case .configWriteFailed(let message):
            return "Failed to manage RTK configuration: \(message)"
        }
    }
}

enum RTKConfigManager {
    private static let testHomeEnvKey = "JIN_RTK_HOME"

    static func configurationFileURL() throws -> URL {
        guard let root = configurationRootDirectoryURL() else {
            throw RTKRuntimeError.configDirectoryUnavailable
        }
        return root
            .appendingPathComponent("rtk", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
    }

    static func teeDirectoryURL() throws -> URL {
        let baseDirectory: URL
        if let overrideHome = overrideHomeDirectoryURL() {
            baseDirectory = overrideHome
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = appSupport
        } else {
            throw RTKRuntimeError.configDirectoryUnavailable
        }

        return baseDirectory
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("RTK", isDirectory: true)
            .appendingPathComponent("tee", isDirectory: true)
    }

    static func managedHomeDirectoryPath() -> String? {
        overrideHomeDirectoryURL()?.path
    }

    static func ensureManagedConfiguration() throws {
        let configURL = try configurationFileURL()
        let teeDirectoryURL = try teeDirectoryURL()

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: teeDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        let managedSection = makeManagedTeeSection(directoryPath: teeDirectoryURL.path)
        let updatedContents: String

        if fileManager.fileExists(atPath: configURL.path) {
            let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            updatedContents = replacingTeeSection(in: existing, with: managedSection)
        } else {
            updatedContents = managedSection
        }

        do {
            try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw RTKRuntimeError.configWriteFailed(error.localizedDescription)
        }
    }

    private static func overrideHomeDirectoryURL() -> URL? {
        guard let value = ProcessInfo.processInfo.environment[testHomeEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    private static func configurationRootDirectoryURL() -> URL? {
        if let overrideHome = overrideHomeDirectoryURL() {
            return overrideHome
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static func makeManagedTeeSection(directoryPath: String) -> String {
        let escapedDirectory = directoryPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        [tee]
        enabled = true
        mode = "always"
        max_files = 20
        max_file_size = 1048576
        directory = "\(escapedDirectory)"

        """
    }

    private static func replacingTeeSection(in contents: String, with managedSection: String) -> String {
        let lines = contents.components(separatedBy: .newlines)
        var output: [String] = []
        var skippingTeeSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isSectionHeader = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")

            if skippingTeeSection {
                if isSectionHeader && trimmed != "[tee]" {
                    skippingTeeSection = false
                    output.append(line)
                }
                continue
            }

            if trimmed == "[tee]" {
                skippingTeeSection = true
                continue
            }

            output.append(line)
        }

        var normalized = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            normalized += "\n\n"
        }
        normalized += managedSection
        return normalized
    }
}

enum RTKRuntimeSupport {
    static let embeddedVersion = "0.31.0"
    private static let helperOverrideEnvKey = "JIN_RTK_PATH"
    private static let teeDirectoryOverrideEnvKey = "RTK_TEE_DIR"
    private static let fullOutputPrefix = "[full output:"

    static func status() async -> RTKRuntimeStatus {
        let configURL = (try? RTKConfigManager.configurationFileURL()) ?? URL(fileURLWithPath: "/")
        let teeDirectoryURL = (try? RTKConfigManager.teeDirectoryURL()) ?? URL(fileURLWithPath: "/")

        do {
            let helperURL = try helperExecutableURL()
            let version = try await versionString()
            return RTKRuntimeStatus(
                helperURL: helperURL,
                helperVersion: version,
                configURL: configURL,
                teeDirectoryURL: teeDirectoryURL,
                errorDescription: nil
            )
        } catch {
            return RTKRuntimeStatus(
                helperURL: helperExecutableURLIfAvailable(),
                helperVersion: nil,
                configURL: configURL,
                teeDirectoryURL: teeDirectoryURL,
                errorDescription: error.localizedDescription
            )
        }
    }

    static func helperExecutableURLIfAvailable() -> URL? {
        if let overrideValue = ProcessInfo.processInfo.environment[helperOverrideEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overrideValue.isEmpty {
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
        if let overrideValue = ProcessInfo.processInfo.environment[helperOverrideEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overrideValue.isEmpty {
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
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "rtk \(embeddedVersion)" : output
    }

    static func prepareShellCommand(_ command: String) async throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
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

        let rewritten = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func resolveRawOutputPath(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(fullOutputPrefix), trimmed.hasSuffix("]") else { continue }

            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: fullOutputPrefix.count)
            let rawPath = trimmed[startIndex..<trimmed.index(before: trimmed.endIndex)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawPath.isEmpty else { continue }

            let resolvedPath: String
            if rawPath.hasPrefix("~/") {
                resolvedPath = FileManager.default.homeDirectoryForCurrentUser.path + String(rawPath.dropFirst(1))
            } else {
                resolvedPath = rawPath
            }

            let standardized = URL(fileURLWithPath: resolvedPath).standardizedFileURL.path
            return standardized
        }
        return nil
    }

    private static func combinedOutput(stdout: String, stderr: String) -> String {
        var output = stdout
        if !stderr.isEmpty {
            if !output.isEmpty {
                output += "\n\n"
            }
            output += "[stderr]\n\(stderr)"
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "(no output)"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func managedEnvironment(helperURL: URL) throws -> [String: String] {
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
}
