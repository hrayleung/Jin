import Foundation
import SQLite3
import XCTest
@testable import Jin

final class StoreCompactionTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        suiteName = "jin.tests.compaction.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Threshold policy

    func testShouldCompactRequiresBothSizeAndProportion() {
        let pageSize: Int64 = 4096

        // Half the file is free, but it's a small file — not worth a rewrite.
        XCTAssertFalse(StoreCompaction.shouldCompact(
            stats: SQLiteSpaceStats(pageSize: pageSize, pageCount: 200, freeListCount: 100)
        ))

        // Plenty of free bytes, but a rounding error of the whole file.
        XCTAssertFalse(StoreCompaction.shouldCompact(
            stats: SQLiteSpaceStats(pageSize: pageSize, pageCount: 1_000_000, freeListCount: 5_000)
        ))

        // 20 MB free and 20% of the file.
        XCTAssertTrue(StoreCompaction.shouldCompact(
            stats: SQLiteSpaceStats(pageSize: pageSize, pageCount: 25_600, freeListCount: 5_120)
        ))

        XCTAssertFalse(StoreCompaction.shouldCompact(stats: nil))
    }

    func testPendingFlagRoundTrip() {
        XCTAssertFalse(StoreCompaction.isPending(defaults: defaults))
        StoreCompaction.markPending(defaults: defaults)
        XCTAssertTrue(StoreCompaction.isPending(defaults: defaults))
        StoreCompaction.clearPending(defaults: defaults)
        XCTAssertFalse(StoreCompaction.isPending(defaults: defaults))
    }

    // MARK: - Real VACUUM

    func testVacuumReclaimsFreePagesAndShrinksTheFile() throws {
        let storeURL = directory.appendingPathComponent("test.store")
        try makeDatabase(at: storeURL, blobCount: 1_500, blobBytes: 8_192)

        let filled = try XCTUnwrap(SQLiteDatabaseSupport.spaceStats(at: storeURL))
        XCTAssertEqual(filled.freeListCount, 0)
        let filledFileSize = try fileSize(of: storeURL)

        try execute("DELETE FROM blobs;", at: storeURL)

        let afterDelete = try XCTUnwrap(SQLiteDatabaseSupport.spaceStats(at: storeURL))
        XCTAssertGreaterThan(afterDelete.freeListCount, 0, "Deleting rows should park pages on the free list.")
        XCTAssertEqual(
            try fileSize(of: storeURL),
            filledFileSize,
            "SQLite must not shrink the file on its own — this is the whole reason compaction exists."
        )

        try SQLiteDatabaseSupport.vacuum(at: storeURL)

        let afterVacuum = try XCTUnwrap(SQLiteDatabaseSupport.spaceStats(at: storeURL))
        XCTAssertEqual(afterVacuum.freeListCount, 0)
        XCTAssertLessThan(try fileSize(of: storeURL), filledFileSize / 2)
    }

    func testPerformPendingCompactionOnlyRunsWhenMarkedAndWorthIt() throws {
        let storeURL = directory.appendingPathComponent("marked.store")
        try makeDatabase(at: storeURL, blobCount: 3_000, blobBytes: 8_192)
        try execute("DELETE FROM blobs;", at: storeURL)
        let beforeSize = try fileSize(of: storeURL)

        // Not marked: nothing happens even though there is plenty to reclaim.
        XCTAssertFalse(StoreCompaction.performPendingCompaction(storeURL: storeURL, defaults: defaults))
        XCTAssertEqual(try fileSize(of: storeURL), beforeSize)

        StoreCompaction.markPending(defaults: defaults)
        XCTAssertTrue(StoreCompaction.performPendingCompaction(storeURL: storeURL, defaults: defaults))
        XCTAssertLessThan(try fileSize(of: storeURL), beforeSize / 2)
        XCTAssertFalse(
            StoreCompaction.isPending(defaults: defaults),
            "A successful compaction must clear the flag so the next launch isn't slowed again."
        )
    }

    func testPerformPendingCompactionClearsTheFlagWhenThereIsNothingToReclaim() throws {
        let storeURL = directory.appendingPathComponent("small.store")
        try makeDatabase(at: storeURL, blobCount: 10, blobBytes: 128)
        StoreCompaction.markPending(defaults: defaults)

        XCTAssertFalse(StoreCompaction.performPendingCompaction(storeURL: storeURL, defaults: defaults))
        XCTAssertFalse(StoreCompaction.isPending(defaults: defaults))
    }

    func testPerformPendingCompactionClearsTheFlagWhenTheStoreIsMissing() {
        StoreCompaction.markPending(defaults: defaults)
        let missing = directory.appendingPathComponent("nope.store")

        XCTAssertFalse(StoreCompaction.performPendingCompaction(storeURL: missing, defaults: defaults))
        XCTAssertFalse(StoreCompaction.isPending(defaults: defaults))
    }

    // MARK: - Helpers

    private func fileSize(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func makeDatabase(at url: URL, blobCount: Int, blobBytes: Int) throws {
        try execute(
            """
            CREATE TABLE blobs (id INTEGER PRIMARY KEY, payload BLOB);
            WITH RECURSIVE counter(x) AS (
                SELECT 1 UNION ALL SELECT x + 1 FROM counter WHERE x < \(blobCount)
            )
            INSERT INTO blobs (payload) SELECT randomblob(\(blobBytes)) FROM counter;
            """,
            at: url
        )
    }

    private func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw XCTSkip("Could not open the temporary SQLite database.")
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqlite3_errmsg(database).map { String(cString: $0) } ?? "unknown"
            XCTFail("SQLite statement failed: \(message)")
            return
        }
    }
}
