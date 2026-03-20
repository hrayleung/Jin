import XCTest
@testable import Jin

final class AgentWorkingDirectorySupportTests: XCTestCase {
    func testNormalizedPathExpandsTildeAndTrimsWhitespace() {
        let normalized = AgentWorkingDirectorySupport.normalizedPath(from: "  ~/Projects/test  ")
        XCTAssertTrue(normalized.hasPrefix(NSHomeDirectory()))
        XCTAssertTrue(normalized.hasSuffix("/Projects/test"))
    }

    func testValidationStateForEmptyPath() {
        XCTAssertEqual(
            AgentWorkingDirectorySupport.validationState(for: "   "),
            .empty
        )
    }

    func testValidationStateForExistingDirectory() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentWorkingDirectorySupportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertEqual(
            AgentWorkingDirectorySupport.validationState(for: directoryURL.path),
            .valid(directoryURL.path)
        )
    }

    func testValidationStateForMissingDirectory() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentWorkingDirectorySupportTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nonexistent", isDirectory: true)
            .path

        XCTAssertEqual(
            AgentWorkingDirectorySupport.validationState(for: missingPath),
            .missing(missingPath)
        )
    }

    func testValidationStateForFilePath() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentWorkingDirectorySupportTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("file.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertEqual(
            AgentWorkingDirectorySupport.validationState(for: fileURL.path),
            .notDirectory(fileURL.path)
        )
    }
}
