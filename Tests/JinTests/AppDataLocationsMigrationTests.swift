import XCTest
@testable import Jin

final class AppDataLocationsMigrationTests: XCTestCase {
    func testMigrationMovesLegacyStoreAndAttachmentDataIntoSharedRoot() throws {
        let previousRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            if let previousRoot {
                setenv("JIN_APP_SUPPORT_ROOT", previousRoot, 1)
            } else {
                unsetenv("JIN_APP_SUPPORT_ROOT")
            }
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)

        let legacyStoreURL = temporaryRoot.appendingPathComponent(AppDataLocations.storeFileName)
        let legacyAttachmentsDirectory = temporaryRoot
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        let legacyCacheFile = temporaryRoot
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("SearchRedirectURLCache.json", isDirectory: false)
        let legacyNetworkTraceFile = temporaryRoot
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("network-trace", isDirectory: true)
            .appendingPathComponent("trace.json", isDirectory: false)
        let legacyBackupStore = temporaryRoot
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("backup-test", isDirectory: true)
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)

        try XCTUnwrap("db".data(using: .utf8)).write(to: legacyStoreURL)
        try FileManager.default.createDirectory(at: legacyAttachmentsDirectory, withIntermediateDirectories: true)
        try XCTUnwrap("attachment".data(using: .utf8))
            .write(to: legacyAttachmentsDirectory.appendingPathComponent("note.txt"))
        try FileManager.default.createDirectory(at: legacyCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap("{}".data(using: .utf8)).write(to: legacyCacheFile)
        try FileManager.default.createDirectory(at: legacyNetworkTraceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap("{\"trace\":true}".data(using: .utf8)).write(to: legacyNetworkTraceFile)
        try FileManager.default.createDirectory(at: legacyBackupStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap("backup".data(using: .utf8)).write(to: legacyBackupStore)

        try AppDataLocations.migrateLegacyDataIfNeeded()

        let migratedStoreURL = try AppDataLocations.storeURL()
        let migratedAttachmentURL = try AppDataLocations.attachmentsDirectoryURL()
            .appendingPathComponent("note.txt")
        let migratedCacheURL = try AppDataLocations.searchRedirectCacheFileURL()
        let migratedNetworkTraceURL = try AppDataLocations.networkTraceDirectoryURL()
            .appendingPathComponent("trace.json")
        let migratedBackupURL = try AppDataLocations.snapshotsDirectoryURL()
            .appendingPathComponent("backup-test", isDirectory: true)
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedStoreURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedAttachmentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedCacheURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedNetworkTraceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedBackupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyStoreURL.path))
    }
}
