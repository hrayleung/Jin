import XCTest
@testable import Jin

final class HistoricalMessagePartLoaderTests: XCTestCase {
    func testLoadsDeferredFileExtractedTextFromStoredContentData() throws {
        let expectedText = String(repeating: "Extracted PDF text. ", count: 40)
        let message = Message(
            id: UUID(),
            role: .user,
            content: [
                .file(
                    FileContent(
                        mimeType: "application/pdf",
                        filename: "report.pdf",
                        data: nil,
                        url: URL(fileURLWithPath: "/tmp/report.pdf"),
                        extractedText: expectedText
                    )
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let text = HistoricalMessagePartLoader.fileExtractedText(
            from: entity.contentData,
            partIndex: 0
        )

        XCTAssertEqual(text, expectedText)
    }

    func testLoadsDeferredInlineImageDataFromStoredContentData() throws {
        let expectedData = Data([0x89, 0x50, 0x4E, 0x47])
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .image(
                    ImageContent(
                        mimeType: "image/png",
                        data: expectedData,
                        url: nil,
                        assetDisposition: .managed
                    )
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let data = HistoricalMessagePartLoader.imageData(
            from: entity.contentData,
            partIndex: 0
        )

        XCTAssertEqual(data, expectedData)
    }
}
