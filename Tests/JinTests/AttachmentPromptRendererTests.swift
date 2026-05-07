import XCTest
@testable import Jin

final class AttachmentPromptRendererTests: XCTestCase {
    func testFallbackTextUsesTrimmedExtractedTextWhenPresent() {
        let file = fileContent(
            mimeType: "application/pdf",
            filename: "notes.pdf",
            extractedText: " # Notes\n"
        )

        XCTAssertTrue(AttachmentPromptRenderer.fallbackText(for: file).hasSuffix("\n\n# Notes"))
    }

    func testFallbackTextUsesAttachmentSummaryForBlankExtractedText() {
        let file = fileContent(
            mimeType: "text/plain",
            filename: "notes.txt",
            extractedText: " \n\t "
        )

        XCTAssertEqual(
            AttachmentPromptRenderer.fallbackText(for: file),
            "Attachment: notes.txt (text/plain)"
        )
    }

    private func fileContent(
        mimeType: String,
        filename: String,
        extractedText: String?
    ) -> FileContent {
        FileContent(
            mimeType: mimeType,
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            extractedText: extractedText
        )
    }
}
