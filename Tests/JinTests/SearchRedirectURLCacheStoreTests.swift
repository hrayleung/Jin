import XCTest
@testable import Jin

final class SearchRedirectURLCacheStoreTests: XCTestCase {
    func testLoadDecodesSupportedTimestampFormatsAndFiltersExpiredEntries() throws {
        let cache = try makeTemporarySearchRedirectCacheStoreURL(prefix: "search-redirect-cache-store-load")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-8 * 24 * 60 * 60)

        let json = """
        {
          "version": 1,
          "entries": {
            "https://example.com/double": {
              "resolvedURL": "https://resolved.example/double",
              "resolvedAt": \(recent.timeIntervalSince1970)
            },
            "https://example.com/int": {
              "resolvedURL": null,
              "resolvedAt": \(Int(recent.timeIntervalSince1970))
            },
            "https://example.com/string": {
              "resolvedURL": "https://resolved.example/string",
              "resolvedAt": "\(recent.timeIntervalSince1970)"
            },
            "https://example.com/stale": {
              "resolvedURL": "https://resolved.example/stale",
              "resolvedAt": \(stale.timeIntervalSince1970)
            }
          }
        }
        """
        try Data(json.utf8).write(to: cache.fileURL)

        let loaded = SearchRedirectURLCacheStore.load(from: cache.fileURL, now: now)

        XCTAssertEqual(loaded["https://example.com/double"]?.resolvedURL, "https://resolved.example/double")
        XCTAssertNil(loaded["https://example.com/int"]?.resolvedURL)
        XCTAssertEqual(loaded["https://example.com/string"]?.resolvedURL, "https://resolved.example/string")
        XCTAssertNil(loaded["https://example.com/stale"])
    }

    func testLoadRejectsUnsupportedVersionsAndMalformedPayloads() throws {
        let cache = try makeTemporarySearchRedirectCacheStoreURL(prefix: "search-redirect-cache-store-invalid")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        try Data(#"{"version":2,"entries":{}}"#.utf8).write(to: cache.fileURL)
        XCTAssertEqual(SearchRedirectURLCacheStore.load(from: cache.fileURL, now: Date()), [:])

        try Data(#"{"version":1,"entries":{"url":{"resolvedAt":{}}}}"#.utf8).write(to: cache.fileURL)
        XCTAssertEqual(SearchRedirectURLCacheStore.load(from: cache.fileURL, now: Date()), [:])
    }

    func testPersistWritesOnlyFreshEntriesAndRoundTripsNilResolvedURL() throws {
        let cache = try makeTemporarySearchRedirectCacheStoreURL(prefix: "search-redirect-cache-store-persist")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let now = Date(timeIntervalSince1970: 2_000_000)
        SearchRedirectURLCacheStore.persist(
            [
                "https://example.com/fresh": SearchRedirectURLCacheStore.Entry(
                    resolvedURL: nil,
                    resolvedAt: now.addingTimeInterval(-60)
                ),
                "https://example.com/stale": SearchRedirectURLCacheStore.Entry(
                    resolvedURL: "https://resolved.example/stale",
                    resolvedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
                )
            ],
            to: cache.fileURL,
            fileManager: .default,
            now: now
        )

        let loaded = SearchRedirectURLCacheStore.load(from: cache.fileURL, now: now)

        XCTAssertEqual(Array(loaded.keys), ["https://example.com/fresh"])
        XCTAssertNil(loaded["https://example.com/fresh"]?.resolvedURL)
    }

    func testPersistRemovesCacheFileWhenNoFreshEntriesRemain() throws {
        let cache = try makeTemporarySearchRedirectCacheStoreURL(prefix: "search-redirect-cache-store-remove")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        try Data("stale".utf8).write(to: cache.fileURL)

        let now = Date(timeIntervalSince1970: 3_000_000)
        SearchRedirectURLCacheStore.persist(
            [
                "https://example.com/stale": SearchRedirectURLCacheStore.Entry(
                    resolvedURL: "https://resolved.example/stale",
                    resolvedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
                )
            ],
            to: cache.fileURL,
            fileManager: .default,
            now: now
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL.path))
    }
}

private func makeTemporarySearchRedirectCacheStoreURL(prefix: String) throws -> (directory: URL, fileURL: URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory, directory.appendingPathComponent("cache.json"))
}
