import Foundation

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
        } else if let rtkDirectory = try? AppDataLocations.rtkDirectoryURL() {
            return rtkDirectory.appendingPathComponent("tee", isDirectory: true)
        } else {
            throw RTKRuntimeError.configDirectoryUnavailable
        }

        return baseDirectory
            .appendingPathComponent(AppDataLocations.sharedDirectoryName, isDirectory: true)
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
        return try? AppDataLocations.applicationSupportDirectory()
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
