import XCTest
@testable import Jin

final class ManagedAgentUIVisibilitySupportTests: XCTestCase {
    func testClaudeManagedAgentsHideInternalUI() {
        XCTAssertTrue(ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: .claudeManagedAgents))
        XCTAssertFalse(ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: .anthropic))
        XCTAssertFalse(ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: nil))
    }

    func testManagedAgentHidesThinkingBlocksButKeepsTextAndArtifactsVisible() {
        let thinkingBlock = RenderedMessageBlock.content(
            anchorID: "thinking",
            part: .thinking(ThinkingBlock(text: "internal", signature: nil, provider: nil))
        )
        let textBlock = RenderedMessageBlock.content(anchorID: "text", part: .text("visible"))
        let artifactBlock = RenderedMessageBlock.artifact(
            RenderedArtifactVersion(
                artifactID: "artifact",
                version: 1,
                title: "Artifact",
                contentType: .html,
                content: "<p>Hello</p>",
                sourceMessageID: UUID(),
                sourceTimestamp: Date()
            )
        )

        XCTAssertFalse(
            ManagedAgentUIVisibilitySupport.isVisibleRenderedBlock(
                thinkingBlock,
                providerType: .claudeManagedAgents
            )
        )
        XCTAssertTrue(
            ManagedAgentUIVisibilitySupport.isVisibleRenderedBlock(
                thinkingBlock,
                providerType: .anthropic
            )
        )
        XCTAssertTrue(
            ManagedAgentUIVisibilitySupport.isVisibleRenderedBlock(
                textBlock,
                providerType: .claudeManagedAgents
            )
        )
        XCTAssertTrue(
            ManagedAgentUIVisibilitySupport.isVisibleRenderedBlock(
                artifactBlock,
                providerType: .claudeManagedAgents
            )
        )
    }
}
