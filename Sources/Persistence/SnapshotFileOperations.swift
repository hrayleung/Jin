import Foundation

enum SnapshotFileOperations {
    static func replaceDirectory(at liveURL: URL, with sourceURL: URL) throws {
        let stagedReplacement = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(liveURL.lastPathComponent)-replacement-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: stagedReplacement.path) {
            try FileManager.default.removeItem(at: stagedReplacement)
        }
        try FileManager.default.copyItem(at: sourceURL, to: stagedReplacement)

        if FileManager.default.fileExists(atPath: liveURL.path) {
            _ = try FileManager.default.replaceItemAt(
                liveURL,
                withItemAt: stagedReplacement,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            let parentDirectory = liveURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDirectory.path) {
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            }
            try FileManager.default.moveItem(at: stagedReplacement, to: liveURL)
        }
    }

    static func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    static func removeTransientPreferenceSnapshotFile(from preferencesDirectory: URL) {
        let snapshotPreferenceURL = preferencesDirectory
            .appendingPathComponent(AppDataLocations.snapshotPreferencesFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: snapshotPreferenceURL.path) else { return }
        try? FileManager.default.removeItem(at: snapshotPreferenceURL)
    }

    static func extractArchiveToTemporaryDirectory(_ archiveURL: URL) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        do {
            try runDitto(arguments: ["-x", "-k", archiveURL.path, temporaryDirectory.path])
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
        return temporaryDirectory
    }

    static func locateSnapshotDirectory(in extractedDirectory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractedDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        if let directMatch = contents.first(where: {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false).path
            )
        }) {
            return directMatch
        }

        if FileManager.default.fileExists(
            atPath: extractedDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false).path
        ) {
            return extractedDirectory
        }

        throw SnapshotError.invalidSnapshot("Imported archive does not contain a valid Jin snapshot.")
    }

    static func snapshotPrimaryStoreURL(in snapshotDirectory: URL) -> URL? {
        let nestedStoreURL = snapshotDirectory
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: nestedStoreURL.path) {
            return nestedStoreURL
        }

        let legacyStoreURL = snapshotDirectory
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: legacyStoreURL.path) {
            return legacyStoreURL
        }

        return nil
    }

    static func copySnapshotDatabaseArtifacts(from snapshotDirectory: URL, to destinationDirectory: URL) throws {
        guard let sourceStoreURL = snapshotPrimaryStoreURL(in: snapshotDirectory) else {
            throw SnapshotError.invalidSnapshot("Snapshot database is missing.")
        }

        let sourceParentDirectory = sourceStoreURL.deletingLastPathComponent()
        let fileNames = [
            AppDataLocations.storeFileName,
            "\(AppDataLocations.storeFileName)-shm",
            "\(AppDataLocations.storeFileName)-wal"
        ]

        for fileName in fileNames {
            let sourceURL = sourceParentDirectory.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = destinationDirectory.appendingPathComponent(fileName, isDirectory: false)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SnapshotError.exportFailed(message?.isEmpty == false ? message! : "ditto failed.")
        }
    }
}
