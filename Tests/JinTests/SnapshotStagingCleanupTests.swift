import Foundation
import XCTest
@testable import Jin

/// A snapshot capture stages a full copy of the store *and* every attachment
/// in a dot-prefixed directory. When one is left behind it becomes a hidden,
/// permanent duplicate of the whole library that the snapshot pruner can't
/// see — which is how a 3.9 GB orphan can sit on disk for months.
final class SnapshotStagingCleanupTests: XCTestCase {

    private var previousAppSupportRoot: String?
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousAppSupportRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)
    }

    override func tearDownWithError() throws {
        if let previousAppSupportRoot {
            setenv("JIN_APP_SUPPORT_ROOT", previousAppSupportRoot, 1)
        } else {
            unsetenv("JIN_APP_SUPPORT_ROOT")
        }
        try? FileManager.default.removeItem(at: temporaryRoot)
        try super.tearDownWithError()
    }

    func testPruneRemovesAbandonedStagingBundlesOnly() throws {
        let snapshots = try AppDataLocations.snapshotsDirectoryURL()
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)

        let abandoned = try makeDirectory(in: snapshots, named: "\(AppSnapshotManager.stagingDirectoryPrefix)old")
        let inProgress = try makeDirectory(in: snapshots, named: "\(AppSnapshotManager.stagingDirectoryPrefix)live")
        let realSnapshot = try makeDirectory(in: snapshots, named: "snapshot-2026-01-01T000000-abcdef12")

        try age(abandoned, by: AppSnapshotManager.stagingStaleAge + 60)
        try age(realSnapshot, by: AppSnapshotManager.stagingStaleAge * 100)

        AppSnapshotManager.pruneStaleStagingDirectories()

        XCTAssertFalse(exists(abandoned), "A staging bundle untouched for an hour is abandoned.")
        XCTAssertTrue(exists(inProgress), "A staging bundle still being written must survive.")
        XCTAssertTrue(exists(realSnapshot), "Real snapshots are never staging bundles, whatever their age.")
    }

    func testPruneIsSafeWithNoSnapshotsDirectory() {
        // No directory created — must not throw or crash.
        AppSnapshotManager.pruneStaleStagingDirectories()
    }

    /// The pruner has to look at hidden entries; `listSnapshots()` deliberately
    /// doesn't, which is precisely why the leak went unnoticed.
    func testStagingBundlesAreInvisibleToSnapshotListing() throws {
        let snapshots = try AppDataLocations.snapshotsDirectoryURL()
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        _ = try makeDirectory(in: snapshots, named: "\(AppSnapshotManager.stagingDirectoryPrefix)hidden")

        XCTAssertTrue(AppSnapshotManager.listSnapshots().isEmpty)
    }

    // MARK: - Helpers

    private func makeDirectory(in parent: URL, named name: String) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Give it some content so it's a realistic bundle, not an empty shell.
        try Data("payload".utf8).write(to: url.appendingPathComponent("payload.bin"))
        return url
    }

    private func age(_ url: URL, by interval: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -interval)],
            ofItemAtPath: url.path
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
