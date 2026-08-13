import XCTest
@testable import Jin

@MainActor
final class ChatStreamingToolLoopPresentationTests: XCTestCase {
    func testClearingLiveBubbleAfterPersistDropsClonedToolCalls() {
        let state = StreamingMessageState()
        let call = ToolCall(
            id: "fetch_1",
            name: "tinyfish__fetch_content",
            arguments: ["url": AnyCodable("https://tinyfish.ai")]
        )
        state.appendDeltas(textDelta: "Looking that up.", thinkingDelta: "")
        state.setToolCalls([call])
        XCTAssertTrue(state.hasVisiblePresentation)
        XCTAssertEqual(state.streamingToolCalls.map(\.id), ["fetch_1"])

        ChatStreamingOrchestrator.clearLiveBubbleAfterPersistingToolTurn(state)

        XCTAssertFalse(state.hasVisiblePresentation)
        XCTAssertTrue(state.streamingToolCalls.isEmpty)
        XCTAssertTrue(state.toolResultsByCallID.isEmpty)
        XCTAssertFalse(state.hasVisibleText)
        XCTAssertEqual(state.visibleText, "")
    }
}
