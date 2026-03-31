import XCTest
@testable import Jin

final class ChatTimelinePayloadResolverFactoryTests: XCTestCase {
    func testContentDataByMessageIDExtractsStoredPayloadsFromEntities() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [.text("Hello")],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let entity = try MessageEntity.fromDomain(message)

        let result = ChatTimelinePayloadResolverFactory.contentDataByMessageID(
            messageEntitiesByID: [message.id: entity]
        )

        XCTAssertEqual(result, [message.id: entity.contentData])
    }

    func testMakeLoadsDeferredImageDataFromStoredContentData() async throws {
        let messageID = UUID()
        let expectedData = Data([0x89, 0x50, 0x4E, 0x47])
        let message = Message(
            id: messageID,
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
        let resolver = ChatTimelinePayloadResolverFactory.make(messageEntitiesByID: [messageID: entity])

        let data = await resolver.loadImageData(
            DeferredMessagePartReference(messageID: messageID, partIndex: 0)
        )

        XCTAssertEqual(data, expectedData)
    }

    func testMakeLoadsDeferredFileExtractedTextFromStoredContentData() async throws {
        let messageID = UUID()
        let expectedText = String(repeating: "Extracted text ", count: 20)
        let message = Message(
            id: messageID,
            role: .user,
            content: [
                .file(
                    FileContent(
                        mimeType: "application/pdf",
                        filename: "notes.pdf",
                        data: nil,
                        url: URL(fileURLWithPath: "/tmp/notes.pdf"),
                        extractedText: expectedText
                    )
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let entity = try MessageEntity.fromDomain(message)
        let resolver = ChatTimelinePayloadResolverFactory.make(messageEntitiesByID: [messageID: entity])

        let text = await resolver.loadFileExtractedText(
            DeferredMessagePartReference(messageID: messageID, partIndex: 0)
        )

        XCTAssertEqual(text, expectedText)
    }

    func testMakeReturnsNilWhenMessagePayloadIsUnavailable() async {
        let resolver = ChatTimelinePayloadResolverFactory.make(contentDataByMessageID: [:])

        let imageData = await resolver.loadImageData(
            DeferredMessagePartReference(messageID: UUID(), partIndex: 0)
        )
        let extractedText = await resolver.loadFileExtractedText(
            DeferredMessagePartReference(messageID: UUID(), partIndex: 0)
        )

        XCTAssertNil(imageData)
        XCTAssertNil(extractedText)
    }
}
