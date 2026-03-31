import XCTest
@testable import Jin

final class ChatMessageRenderPipelineHeuristicsTests: XCTestCase {
    func testRenderMetadataPrefersNativeTextForSinglePlainAssistantTextBlock() {
        let content: [RenderedContentPart] = [.text("Plain answer without markdown syntax.")]
        let renderedBlocks: [RenderedMessageBlock] = [.content(.text("Plain answer without markdown syntax."))]

        let metadata = ChatMessageRenderMetadataBuilder.renderMetadata(
            role: .assistant,
            content: content,
            renderedBlocks: renderedBlocks,
            copyText: "Plain answer without markdown syntax."
        )

        XCTAssertEqual(metadata.preferredRenderMode, .nativeText)
        XCTAssertFalse(metadata.isMemoryIntensiveAssistantContent)
        XCTAssertNil(metadata.collapsedPreview)
    }

    func testRenderMetadataCreatesArtifactOnlyPreviewFromArtifactBlocks() {
        let artifact = RenderedArtifactVersion(
            artifactID: "demo",
            version: 1,
            title: "Sales Dashboard",
            contentType: .html,
            content: "<div>artifact</div>",
            sourceMessageID: UUID(),
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )

        let metadata = ChatMessageRenderMetadataBuilder.renderMetadata(
            role: .assistant,
            content: [.text("<jinArtifact artifact_id=\"demo\" title=\"Sales Dashboard\" contentType=\"text/html\"><div>artifact</div></jinArtifact>")],
            renderedBlocks: [.artifact(artifact)],
            copyText: ""
        )

        XCTAssertEqual(metadata.preferredRenderMode, .fullWeb)
        XCTAssertTrue(metadata.isMemoryIntensiveAssistantContent)
        XCTAssertEqual(metadata.collapsedPreview?.headline, "Sales Dashboard")
        XCTAssertEqual(metadata.collapsedPreview?.body, "HTML Artifact")
    }

    func testRenderMetadataIgnoresHiddenThinkingWhenVisibleOutputIsSingleTextBlock() {
        let metadata = ChatMessageRenderMetadataBuilder.renderMetadata(
            role: .assistant,
            content: [
                .redactedThinking(RedactedThinkingBlock(data: "hidden")),
                .text("OK")
            ],
            renderedBlocks: [.content(.text("OK"))],
            copyText: "OK"
        )

        XCTAssertEqual(metadata.preferredRenderMode, .nativeText)
    }

    func testAssistantPlainTextPrefersNativeRendering() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [.text("Plain answer without markdown syntax.")],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entity],
            fallbackModelLabel: "GPT",
            assistantProviderIconID: { _ in nil }
        )

        let item = try XCTUnwrap(context.visibleMessages.first)
        XCTAssertEqual(item.preferredRenderMode, .nativeText)
        XCTAssertFalse(item.isMemoryIntensiveAssistantContent)
        XCTAssertNil(item.collapsedPreview)
    }

    func testAssistantCodeBlockPrefersWebRenderingAndProvidesCollapsedPreview() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text(
                    """
                    ```swift
                    struct Demo {
                        let value: Int
                    }
                    ```
                    """
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

        let item = try XCTUnwrap(context.visibleMessages.first)
        XCTAssertEqual(item.preferredRenderMode, .fullWeb)
        XCTAssertTrue(item.isMemoryIntensiveAssistantContent)
        XCTAssertEqual(item.collapsedPreview?.containsCode, true)
    }

    func testAssistantArtifactOnlyReplyStillProvidesCollapsedPreview() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text("<jinArtifact artifact_id=\"demo\" title=\"Sales Dashboard\" contentType=\"text/html\"><div>artifact</div></jinArtifact>")
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let entity = try MessageEntity.fromDomain(message)
        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entity],
            fallbackModelLabel: "GPT",
            assistantProviderIconID: { _ in nil }
        )

        let item = try XCTUnwrap(context.visibleMessages.first)
        XCTAssertTrue(item.isMemoryIntensiveAssistantContent)
        XCTAssertEqual(item.preferredRenderMode, .fullWeb)
        XCTAssertEqual(item.collapsedPreview?.headline, "Sales Dashboard")
        XCTAssertEqual(item.collapsedPreview?.body, "HTML Artifact")
    }
}
