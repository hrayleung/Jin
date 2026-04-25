import Foundation
import XCTest
@testable import Jin

final class SnapshotFileOperationsTests: XCTestCase {
    func testExtractArchiveCleansTemporaryDirectoryWhenDittoFails() throws {
        let fileManager = FileManager.default
        let archiveURL = fileManager.temporaryDirectory
            .appendingPathComponent("invalid-jin-import-\(UUID().uuidString).zip", isDirectory: false)
        try Data("not a zip archive".utf8).write(to: archiveURL)
        defer { try? fileManager.removeItem(at: archiveURL) }

        let before = try jinImportTemporaryDirectoryNames()

        XCTAssertThrowsError(try SnapshotFileOperations.extractArchiveToTemporaryDirectory(archiveURL))

        let after = try jinImportTemporaryDirectoryNames()
        XCTAssertEqual(after.subtracting(before), [])
    }

    private func jinImportTemporaryDirectoryNames() throws -> Set<String> {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return Set(contents.compactMap { url in
            guard url.lastPathComponent.hasPrefix("jin-import-") else { return nil }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return url.lastPathComponent
        })
    }
}
