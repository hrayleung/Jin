import Foundation
import XCTest
@testable import Jin

final class CodexWorkingDirectoryPresetsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CodexWorkingDirectoryPresetsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadNormalizesNameAndPath() {
        let input = [
            CodexWorkingDirectoryPreset(name: "  Jin Repo  ", path: "/tmp//jin/../jin")
        ]

        CodexWorkingDirectoryPresetsStore.save(input, defaults: defaults)
        let loaded = CodexWorkingDirectoryPresetsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Jin Repo")
        XCTAssertEqual(loaded.first?.path, "/tmp/jin")
    }

    func testLoadDropsInvalidAndDeduplicatesByPath() throws {
        let encoded = try JSONEncoder().encode([
            CodexWorkingDirectoryPreset(name: "Relative", path: "tmp/repo"),
            CodexWorkingDirectoryPreset(name: "Primary", path: "/tmp/repo"),
            CodexWorkingDirectoryPreset(name: "Duplicate", path: "/tmp/repo/"),
            CodexWorkingDirectoryPreset(name: "   ", path: "/tmp/fallback")
        ])

        defaults.set(String(decoding: encoded, as: UTF8.self), forKey: AppPreferenceKeys.codexWorkingDirectoryPresetsJSON)
        let loaded = CodexWorkingDirectoryPresetsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Primary")
        XCTAssertEqual(loaded[0].path, "/tmp/repo")
        XCTAssertEqual(loaded[1].name, "fallback")
        XCTAssertEqual(loaded[1].path, "/tmp/fallback")
    }

    func testNormalizedDirectoryPathCanRequireExistingDirectory() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent("note.txt")
        try Data("test".utf8).write(to: tempFile)

        XCTAssertEqual(
            CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(
                from: tempDir.path,
                requireExistingDirectory: true
            ),
            tempDir.standardizedFileURL.path
        )
        XCTAssertNil(
            CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(
                from: tempFile.path,
                requireExistingDirectory: true
            )
        )
        XCTAssertEqual(
            CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(
                from: tempFile.path,
                requireExistingDirectory: false
            ),
            tempFile.standardizedFileURL.path
        )
    }
}
