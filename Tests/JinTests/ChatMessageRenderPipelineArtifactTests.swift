import Collections
import XCTest
@testable import Jin

final class ChatMessageRenderPipelineArtifactTests: XCTestCase {
    func testArtifactBlockBuilderAssignsSequentialVersionsAndVisibleTextBlocks() {
        var artifactVersionCounts: [String: Int] = [:]
        var artifactVersionsByID: OrderedDictionary<String, [RenderedArtifactVersion]> = [:]
        let messageID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1)

        let blocks = ChatArtifactRenderBlockBuilder.renderedBlocks(
            content: [
                .text(
                    """
                    Intro
                    <jinArtifact artifact_id="demo" title="Demo" contentType="text/html"><div>one</div></jinArtifact>
                    Outro
                    """
                )
            ],
            role: .assistant,
            messageID: messageID,
            timestamp: timestamp,
            artifactsEnabled: true,
            artifactVersionCounts: &artifactVersionCounts,
            artifactVersionsByID: &artifactVersionsByID
        )

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(artifactVersionsByID["demo"]?.map(\.version), [1])

        guard case .content(_, .text(let intro)) = blocks[0] else {
            return XCTFail("Expected leading text block")
        }
        XCTAssertTrue(intro.contains("Intro"))

        guard case .artifact(let artifact) = blocks[1] else {
            return XCTFail("Expected artifact block")
        }
        XCTAssertEqual(artifact.version, 1)

        guard case .content(_, .text(let outro)) = blocks[2] else {
            return XCTFail("Expected trailing text block")
        }
        XCTAssertTrue(outro.contains("Outro"))
    }

    func testRenderPipelineBuildsArtifactCatalogAndStripsCopyText() throws {
        let assistantOne = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text(
                    """
                    Intro
                    <jinArtifact artifact_id="demo" title="Demo" contentType="text/html"><div>one</div></jinArtifact>
                    Outro
                    """
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let assistantTwo = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text("<jinArtifact artifact_id=\"demo\" title=\"Demo\" contentType=\"text/html\"><div>two</div></jinArtifact>")
            ],
            timestamp: Date(timeIntervalSince1970: 2)
        )

        let entityOne = try MessageEntity.fromDomain(assistantOne)
        entityOne.generatedProviderID = "openai"
        let entityTwo = try MessageEntity.fromDomain(assistantTwo)
        entityTwo.generatedProviderID = "openai"

        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entityOne, entityTwo],
            fallbackModelLabel: "GPT",
            artifactsEnabled: true,
            assistantProviderIconID: { _ in nil }
        )

        XCTAssertEqual(context.visibleMessages.count, 2)
        XCTAssertEqual(context.artifactCatalog.orderedArtifactIDs, ["demo"])
        XCTAssertEqual(context.artifactCatalog.versions(for: "demo").map(\.version), [1, 2])

        let firstBlocks = context.visibleMessages[0].renderedBlocks
        let firstArtifactBlock = firstBlocks.compactMap { block -> RenderedArtifactVersion? in
            guard case .artifact(let artifact) = block else { return nil }
            return artifact
        }.first
        guard let firstArtifact = firstArtifactBlock else {
            return XCTFail("Expected artifact block in first assistant message")
        }
        XCTAssertEqual(firstArtifact.version, 1)

        XCTAssertTrue(context.visibleMessages[0].copyText.contains("Intro"))
        XCTAssertTrue(context.visibleMessages[0].copyText.contains("Outro"))
        XCTAssertFalse(context.visibleMessages[0].copyText.contains("<jinArtifact"))
        XCTAssertFalse(context.visibleMessages[1].copyText.contains("<jinArtifact"))
    }

    func testRenderPipelineDoesNotParseArtifactsWhenArtifactsAreDisabled() throws {
        let artifactMarkup = #"<jinArtifact artifact_id="demo" title="Demo" contentType="text/html"><div>one</div></jinArtifact>"#
        let assistant = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text(
                    """
                    Before
                    \(artifactMarkup)
                    After
                    """
                )
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let entity = try MessageEntity.fromDomain(assistant)

        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: [entity],
            fallbackModelLabel: "GPT",
            artifactsEnabled: false,
            assistantProviderIconID: { _ in nil }
        )

        XCTAssertTrue(context.artifactCatalog.isEmpty)
        let item = try XCTUnwrap(context.visibleMessages.first)
        XCTAssertEqual(item.renderedBlocks.count, 1)
        XCTAssertTrue(item.copyText.contains("<jinArtifact"))

        guard case .content(_, .text(let text)) = try XCTUnwrap(item.renderedBlocks.first) else {
            return XCTFail("Expected raw artifact markup to remain text when artifacts are disabled")
        }
        XCTAssertTrue(text.contains("<jinArtifact"))
    }

    func testDecodedRenderContextDoesNotParseArtifactsWhenArtifactsAreDisabled() throws {
        let assistant = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text(#"<jinArtifact artifact_id="demo" title="Demo" contentType="text/html"><div>one</div></jinArtifact>"#)
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let entity = try MessageEntity.fromDomain(assistant)

        let context = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(entity)],
            fallbackModelLabel: "GPT",
            artifactsEnabled: false,
            assistantProviderIconsByID: [:]
        )

        XCTAssertTrue(context.artifactCatalog.isEmpty)
        let item = try XCTUnwrap(context.visibleMessages.first)
        XCTAssertEqual(item.renderedBlocks.count, 1)
        XCTAssertTrue(item.copyText.contains("<jinArtifact"))
    }
}
