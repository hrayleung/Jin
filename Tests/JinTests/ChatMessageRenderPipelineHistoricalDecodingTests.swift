import XCTest
@testable import Jin

final class ChatMessageRenderPipelineHistoricalDecodingTests: XCTestCase {
    func testRenderedContentDecoderBuildsDeferredImageReferenceForHistoricalPayloads() throws {
        let messageID = UUID()
        let contentData = Data(
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

        let content = try XCTUnwrap(
            ChatRenderedContentDecoder.renderedContentParts(from: contentData, messageID: messageID)
        )
        let firstPart = try XCTUnwrap(content.first)

        guard case .image(let image) = firstPart else {
            return XCTFail("Expected rendered image part")
        }

        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertEqual(image.deferredSource, DeferredMessagePartReference(messageID: messageID, partIndex: 0))
    }

    func testToolResultIndexBuilderIndexesHistoricalToolSnapshots() throws {
        let toolResult = ToolResult(toolCallID: "call-1", content: "done", isError: false)
        let toolMessage = Message(
            id: UUID(),
            role: .tool,
            content: [.text("tool")],
            toolResults: [toolResult],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let snapshot = PersistedMessageSnapshot(try MessageEntity.fromDomain(toolMessage))
        let results = ChatToolResultIndexBuilder.toolResultsByToolCallID(in: [snapshot])

        XCTAssertEqual(results["call-1"]?.content, "done")
        XCTAssertEqual(results["call-1"]?.isError, false)
    }

    func testDecodedRenderContextKeepsImageMessageWhenInlineImagePayloadIsMalformed() throws {
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
        let message = try XCTUnwrap(context.visibleMessages.first)
        let block = try XCTUnwrap(message.renderedBlocks.first)

        guard case .content(.image(let image)) = block else {
            return XCTFail("Expected lightweight image block")
        }

        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertNotNil(image.deferredSource)
    }

    func testDecodedRenderContextKeepsFileMessageWhenExtractedTextIsMalformed() throws {
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
        let message = try XCTUnwrap(context.visibleMessages.first)
        let block = try XCTUnwrap(message.renderedBlocks.first)

        guard case .content(.file(let file)) = block else {
            return XCTFail("Expected lightweight file block")
        }

        XCTAssertEqual(file.filename, "report.pdf")
        XCTAssertTrue(file.hasDeferredExtractedText)
    }

    func testImmediateRenderContextDoesNotCreateDeferredReferenceForInlineImageData() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .image(
                    ImageContent(
                        mimeType: "image/png",
                        data: Data([0x89, 0x50, 0x4E, 0x47]),
                        url: nil,
                        assetDisposition: .managed
                    )
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entity],
            fallbackModelLabel: "GPT",
            assistantProviderIconID: { _ in nil }
        )

        let renderedMessage = try XCTUnwrap(context.visibleMessages.first)
        let block = try XCTUnwrap(renderedMessage.renderedBlocks.first)

        guard case .content(.image(let image)) = block else {
            return XCTFail("Expected inline image block")
        }

        XCTAssertNotNil(image.inlineData)
        XCTAssertNil(image.deferredSource)
    }

    func testImmediateRenderContextDoesNotCreateDeferredReferenceForFileWithExtractedText() throws {
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
                        extractedText: "Already extracted"
                    )
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entity],
            fallbackModelLabel: "GPT",
            assistantProviderIconID: { _ in nil }
        )

        let renderedMessage = try XCTUnwrap(context.visibleMessages.first)
        let block = try XCTUnwrap(renderedMessage.renderedBlocks.first)

        guard case .content(.file(let file)) = block else {
            return XCTFail("Expected file block")
        }

        XCTAssertEqual(file.extractedText, "Already extracted")
        XCTAssertFalse(file.hasDeferredExtractedText)
        XCTAssertNil(file.deferredSource)
    }
}
