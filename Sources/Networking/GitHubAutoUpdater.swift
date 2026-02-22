import Foundation

enum GitHubAutoUpdateError: LocalizedError {
    case appBundleNotFound
    case unsupportedInstallLocation
    case installLocationNotWritable(String)
    case downloadFailed
    case unzipFailed(String)
    case extractedAppNotFound
    case installerLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .appBundleNotFound:
            return "Could not locate the current app bundle."
        case .unsupportedInstallLocation:
            return "Automatic update is only supported when running from a .app bundle."
        case .installLocationNotWritable(let location):
            return "Cannot install update because '\(location)' is not writable."
        case .downloadFailed:
            return "Failed to download the update archive."
        case .unzipFailed(let message):
            return "Failed to unpack the update archive: \(message)"
        case .extractedAppNotFound:
            return "The downloaded archive does not contain an installable app bundle."
        case .installerLaunchFailed(let message):
            return "Failed to start update installer: \(message)"
        }
    }
}

struct GitHubPreparedUpdate {
    let workingDirectory: URL
    let extractedAppURL: URL
    let targetAppURL: URL
    let installerScriptURL: URL
}

enum GitHubAutoUpdater {
    private static let archiveFileName = "update.zip"
    private static let extractionDirectoryName = "extracted"
    private static let installerScriptFileName = "install-update.sh"

    static func prepareUpdate(
        from asset: GitHubReleaseCandidate.Asset,
        appNameHint: String = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent,
        targetAppURL: URL = Bundle.main.bundleURL
    ) async throws -> GitHubPreparedUpdate {
        try validateInstallTarget(targetAppURL)

        let fileManager = FileManager.default
        let workingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: targetAppURL,
            create: true
        )

        let archiveURL = workingDirectory.appendingPathComponent(archiveFileName, isDirectory: false)
        let extractionDirectory = workingDirectory.appendingPathComponent(extractionDirectoryName, isDirectory: true)
        let installerScriptURL = workingDirectory.appendingPathComponent(installerScriptFileName, isDirectory: false)

        try await downloadArchive(from: asset.downloadURL, to: archiveURL)
        try unpackArchive(at: archiveURL, to: extractionDirectory)
        let extractedAppURL = try locateExtractedApp(in: extractionDirectory, appNameHint: appNameHint)
        try writeInstallerScript(to: installerScriptURL)

        return GitHubPreparedUpdate(
            workingDirectory: workingDirectory,
            extractedAppURL: extractedAppURL,
            targetAppURL: targetAppURL,
            installerScriptURL: installerScriptURL
        )
    }

    static func launchInstaller(using preparedUpdate: GitHubPreparedUpdate) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            preparedUpdate.installerScriptURL.path,
            preparedUpdate.targetAppURL.path,
            preparedUpdate.extractedAppURL.path,
            preparedUpdate.workingDirectory.path
        ]

        do {
            try process.run()
        } catch {
            throw GitHubAutoUpdateError.installerLaunchFailed(error.localizedDescription)
        }
    }

    static func validateInstallTarget(_ targetAppURL: URL) throws {
        let standardizedURL = targetAppURL.standardizedFileURL
        guard standardizedURL.pathExtension.lowercased() == "app" else {
            throw GitHubAutoUpdateError.unsupportedInstallLocation
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: standardizedURL.path) else {
            throw GitHubAutoUpdateError.appBundleNotFound
        }

        let installParent = standardizedURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: installParent.path) else {
            throw GitHubAutoUpdateError.installLocationNotWritable(installParent.path)
        }
    }

    static func locateExtractedApp(in directory: URL, appNameHint: String) throws -> URL {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw GitHubAutoUpdateError.extractedAppNotFound
        }

        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "app" else { continue }
            candidates.append(url)
            enumerator.skipDescendants()
        }

        candidates.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !candidates.isEmpty else {
            throw GitHubAutoUpdateError.extractedAppNotFound
        }

        let normalizedHint = appNameHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedHint.isEmpty {
            if let exactMatch = candidates.first(where: {
                $0.deletingPathExtension()
                    .lastPathComponent
                    .localizedCaseInsensitiveCompare(normalizedHint) == .orderedSame
            }) {
                return exactMatch
            }

            if let partialMatch = candidates.first(where: {
                $0.deletingPathExtension()
                    .lastPathComponent
                    .localizedCaseInsensitiveContains(normalizedHint)
            }) {
                return partialMatch
            }
        }

        return candidates[0]
    }

    private static func downloadArchive(from sourceURL: URL, to destinationURL: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw GitHubAutoUpdateError.downloadFailed
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw GitHubAutoUpdateError.downloadFailed
        }
    }

    private static func unpackArchive(at archiveURL: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.removeItem(at: destinationDirectory)
        }
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        do {
            try runProcess(executable: "/usr/bin/ditto", arguments: [
                "-x",
                "-k",
                archiveURL.path,
                destinationDirectory.path
            ])
        } catch let updateError as GitHubAutoUpdateError {
            throw updateError
        } catch {
            throw GitHubAutoUpdateError.unzipFailed(error.localizedDescription)
        }
    }

    private static func writeInstallerScript(to scriptURL: URL) throws {
        let script = """
        #!/bin/bash
        set -euo pipefail

        TARGET_APP="$1"
        NEW_APP="$2"
        WORK_DIR="$3"

        /bin/sleep 1

        for _ in $(/usr/bin/seq 1 240); do
          if /usr/bin/pgrep -f "$TARGET_APP/Contents/MacOS/" >/dev/null 2>&1; then
            /bin/sleep 0.25
          else
            break
          fi
        done

        if [ -e "$TARGET_APP" ]; then
          /bin/rm -rf "$TARGET_APP"
        fi

        /usr/bin/ditto "$NEW_APP" "$TARGET_APP"
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
        /usr/bin/open "$TARGET_APP"
        /bin/rm -rf "$WORK_DIR"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    @discardableResult
    private static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let combinedOutput = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw GitHubAutoUpdateError.unzipFailed(combinedOutput.isEmpty ? "Unknown error." : combinedOutput)
        }

        return combinedOutput
    }
}
