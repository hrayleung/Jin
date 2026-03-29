import XCTest
@testable import Jin

final class ChatMessageRenderPipelineHistoricalDecodingTests: XCTestCase {
    func testDecodedRenderContextKeepsImageMessageWhenInlineImagePayloadIsMalformed() {
        let entity = MessageEntity(
            role: MessageRole.assistant.rawValue,
            contentData: Data(
                """
                [
                  {
                    "type": "image",
                    "image": {
                      "mimeType": "image/png",
                      "data": "%%%not-base64%%%",
                      "assetDisposition": "managed"
                    }
                  }
                ]
                """.utf8
            )
        )

        let context = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(entity)],
            fallbackModelLabel: "GPT",
            assistantProviderIconsByID: [:]
        )

        XCTAssertEqual(context.visibleMessages.count, 1)
        let message = try? XCTUnwrap(context.visibleMessages.first)
        let block = try? XCTUnwrap(message?.renderedBlocks.first)

        guard case .content(.image(let image)) = block else {
            return XCTFail("Expected lightweight image block")
        }

        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertNotNil(image.deferredSource)
    }

    func testDecodedRenderContextKeepsFileMessageWhenExtractedTextIsMalformed() {
        let entity = MessageEntity(
            role: MessageRole.user.rawValue,
            contentData: Data(
                """
                [
                  {
                    "type": "file",
                    "file": {
                      "mimeType": "application/pdf",
                      "filename": "report.pdf",
                      "url": "file:///tmp/report.pdf",
                      "extractedText": 42
                    }
                  }
                ]
                """.utf8
            )
        )

        let context = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(entity)],
            fallbackModelLabel: "GPT",
            assistantProviderIconsByID: [:]
        )

        XCTAssertEqual(context.visibleMessages.count, 1)
        let message = try? XCTUnwrap(context.visibleMessages.first)
        let block = try? XCTUnwrap(message?.renderedBlocks.first)

        guard case .content(.file(let file)) = block else {
            return XCTFail("Expected lightweight file block")
        }

        XCTAssertEqual(file.filename, "report.pdf")
        XCTAssertTrue(file.hasDeferredExtractedText)
    }
}
