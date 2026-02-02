import XCTest
@testable import Jin

final class ChatDropParsingTests: XCTestCase {
    func testParseDroppedStringExtractsFileURLLines() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("dropped.png")
        try Data().write(to: imageURL, options: [.atomic])

        let result = ChatView.parseDroppedString(imageURL.absoluteString)
        XCTAssertEqual(result.fileURLs.map(\.path), [imageURL.path])
        XCTAssertTrue(result.textChunks.isEmpty)
    }

    func testParseDroppedStringExtractsAbsolutePathsForKnownExtensions() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("doc.pdf")
        try Data().write(to: pdfURL, options: [.atomic])

        let result = ChatView.parseDroppedString(pdfURL.path)
        XCTAssertEqual(result.fileURLs.map(\.path), [pdfURL.path])
        XCTAssertTrue(result.textChunks.isEmpty)
    }

    func testParseDroppedStringKeepsRemoteURLsAsText() {
        let input = "https://example.com/image.png"
        let result = ChatView.parseDroppedString(input)
        XCTAssertTrue(result.fileURLs.isEmpty)
        XCTAssertEqual(result.textChunks, [input])
    }
}

