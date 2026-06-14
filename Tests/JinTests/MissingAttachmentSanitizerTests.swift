import XCTest
@testable import Jin

final class MissingAttachmentSanitizerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Jin-MissingAttachmentSanitizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func missingFileURL(ext: String = "png") -> URL {
        temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    private func existingFileURL(ext: String = "png") throws -> URL {
        let url = missingFileURL(ext: ext)
        try Data("payload".utf8).write(to: url)
        return url
    }

    private func onlyText(_ message: Message) -> String? {
        guard message.content.count == 1, case .text(let text) = message.content[0] else {
            return nil
        }
        return text
    }

    // MARK: - Lost attachments are replaced

    func testMissingImageFileBecomesTextPlaceholder() {
        let image = ImageContent(mimeType: "image/png", url: missingFileURL())
        let message = Message(role: .user, content: [.image(image)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        let text = onlyText(sanitized[0])
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Image attachment omitted") == true)
    }

    func testMissingAudioFileBecomesTextPlaceholder() {
        let audio = AudioContent(mimeType: "audio/mp3", url: missingFileURL(ext: "mp3"))
        let message = Message(role: .user, content: [.audio(audio)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        XCTAssertTrue(onlyText(sanitized[0])?.contains("Audio attachment omitted") == true)
    }

    func testMissingVideoFileBecomesTextPlaceholder() {
        let video = VideoContent(mimeType: "video/mp4", url: missingFileURL(ext: "mp4"))
        let message = Message(role: .user, content: [.video(video)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        XCTAssertTrue(onlyText(sanitized[0])?.contains("Video attachment omitted") == true)
    }

    func testMissingFileReusesFallbackTextAndPreservesExtractedText() {
        let file = FileContent(
            mimeType: "application/pdf",
            filename: "report.pdf",
            url: missingFileURL(ext: "pdf"),
            extractedText: "Quarterly revenue grew 12%."
        )
        let message = Message(role: .user, content: [.file(file)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        let text = onlyText(sanitized[0])
        XCTAssertNotNil(text)
        // Extracted text survives even though the source file is gone.
        XCTAssertTrue(text?.contains("Quarterly revenue grew 12%.") == true)
        XCTAssertTrue(text?.contains("report.pdf") == true)
    }

    // MARK: - Valid attachments are left untouched

    func testExistingImageFileIsUntouched() throws {
        let url = try existingFileURL()
        let image = ImageContent(mimeType: "image/png", url: url)
        let message = Message(role: .user, content: [.image(image)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        guard case .image(let resultImage) = sanitized[0].content[0] else {
            return XCTFail("Expected image part to be preserved")
        }
        XCTAssertEqual(resultImage.url, url)
    }

    func testInlineImageDataIsUntouchedEvenWithMissingURL() {
        let image = ImageContent(
            mimeType: "image/png",
            data: Data("inline".utf8),
            url: missingFileURL()
        )
        let message = Message(role: .user, content: [.image(image)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        guard case .image = sanitized[0].content[0] else {
            return XCTFail("Expected image with inline data to be preserved")
        }
    }

    func testRemoteImageURLIsUntouched() {
        let image = ImageContent(mimeType: "image/png", url: URL(string: "https://example.com/cat.png"))
        let message = Message(role: .user, content: [.image(image)])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        guard case .image(let resultImage) = sanitized[0].content[0] else {
            return XCTFail("Expected remote image to be preserved")
        }
        XCTAssertEqual(resultImage.url?.absoluteString, "https://example.com/cat.png")
    }

    func testTextOnlyMessageReturnedAsSameValue() {
        let message = Message(role: .user, content: [.text("hello")])

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        XCTAssertEqual(onlyText(sanitized[0]), "hello")
    }

    // MARK: - Mixed content & identity preservation

    func testMixedContentReplacesOnlyLostPartsAndKeepsOrder() throws {
        let existingURL = try existingFileURL()
        let parts: [ContentPart] = [
            .text("before"),
            .image(ImageContent(mimeType: "image/png", url: missingFileURL())),
            .image(ImageContent(mimeType: "image/png", url: existingURL)),
            .text("after")
        ]
        let message = Message(role: .user, content: parts)

        let sanitized = MissingAttachmentSanitizer.sanitize([message])
        let result = sanitized[0].content

        XCTAssertEqual(result.count, 4)
        if case .text(let t) = result[0] { XCTAssertEqual(t, "before") } else { XCTFail("part 0") }
        if case .text(let t) = result[1] { XCTAssertTrue(t.contains("Image attachment omitted")) } else { XCTFail("part 1 should be placeholder") }
        if case .image = result[2] {} else { XCTFail("part 2 should remain an image") }
        if case .text(let t) = result[3] { XCTAssertEqual(t, "after") } else { XCTFail("part 3") }
    }

    func testMessageMetadataPreservedWhenRewriting() {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let image = ImageContent(mimeType: "image/png", url: missingFileURL())
        let message = Message(
            id: id,
            role: .assistant,
            content: [.image(image)],
            timestamp: timestamp,
            perMessageMCPServerNames: ["server-a"]
        )

        let sanitized = MissingAttachmentSanitizer.sanitize([message])

        XCTAssertEqual(sanitized[0].id, id)
        XCTAssertEqual(sanitized[0].role, .assistant)
        XCTAssertEqual(sanitized[0].timestamp, timestamp)
        XCTAssertEqual(sanitized[0].perMessageMCPServerNames, ["server-a"])
    }
}
