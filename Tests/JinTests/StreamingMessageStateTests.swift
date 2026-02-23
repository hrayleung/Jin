import XCTest
@testable import Jin

final class StreamingMessageStateTests: XCTestCase {
    func testAppendDeltasIncrementsRenderTickOnce() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "hello", thinkingDelta: "world")

        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(state.textContent, "hello")
        XCTAssertEqual(state.thinkingContent, "world")
    }

    func testAppendDeltasTracksVisibleText() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "   \n\t", thinkingDelta: "")
        XCTAssertFalse(state.hasVisibleText)

        state.appendDeltas(textDelta: "a", thinkingDelta: "")
        XCTAssertTrue(state.hasVisibleText)
    }

    func testResetClearsDerivedState() {
        let state = StreamingMessageState()
        let toolCall = ToolCall(id: "call_1", name: "exa__search", arguments: [:])

        state.appendDeltas(textDelta: "hello", thinkingDelta: "reasoning")
        state.setToolCalls([toolCall])
        state.upsertToolResult(
            ToolResult(toolCallID: "call_1", toolName: "exa__search", content: "ok", isError: false)
        )
        XCTAssertEqual(state.renderTick, 3)
        XCTAssertTrue(state.hasVisibleText)

        state.reset()

        XCTAssertEqual(state.renderTick, 0)
        XCTAssertFalse(state.hasVisibleText)
        XCTAssertEqual(state.textChunks, [])
        XCTAssertEqual(state.thinkingChunks, [])
        XCTAssertEqual(state.textContent, "")
        XCTAssertEqual(state.thinkingContent, "")
        XCTAssertEqual(state.streamingToolCalls.count, 0)
        XCTAssertEqual(state.toolResultsByCallID.count, 0)
    }

    func testUpsertSearchActivityMergesByIDAndIncrementsRenderTick() {
        let state = StreamingMessageState()

        state.upsertSearchActivity(
            SearchActivity(
                id: "ws_1",
                type: "search",
                status: .inProgress,
                arguments: ["query": AnyCodable("swift concurrency")]
            )
        )
        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(state.searchActivities.count, 1)
        XCTAssertEqual(state.searchActivities[0].status, .inProgress)
        XCTAssertEqual(state.searchActivities[0].arguments["query"]?.value as? String, "swift concurrency")

        state.upsertSearchActivity(
            SearchActivity(
                id: "ws_1",
                type: "search",
                status: .completed,
                arguments: ["url": AnyCodable("https://example.com")]
            )
        )

        XCTAssertEqual(state.renderTick, 2)
        XCTAssertEqual(state.searchActivities.count, 1)
        XCTAssertEqual(state.searchActivities[0].status, .completed)
        XCTAssertEqual(state.searchActivities[0].arguments["query"]?.value as? String, "swift concurrency")
        XCTAssertEqual(state.searchActivities[0].arguments["url"]?.value as? String, "https://example.com")
    }

    func testSetToolCallsAndUpsertToolResultTrackResultsByCallID() {
        let state = StreamingMessageState()
        let call = ToolCall(id: "call_1", name: "exa__search", arguments: ["query": AnyCodable("jin")])

        state.setToolCalls([call])

        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(state.streamingToolCalls.count, 1)
        XCTAssertEqual(state.streamingToolCalls.first?.id, "call_1")
        XCTAssertEqual(state.toolResultsByCallID.count, 0)

        state.upsertToolResult(
            ToolResult(toolCallID: "call_1", toolName: "exa__search", content: "done", isError: false)
        )

        XCTAssertEqual(state.renderTick, 2)
        XCTAssertEqual(state.toolResultsByCallID["call_1"]?.content, "done")
    }

    func testUpsertToolResultIgnoresUnknownToolCallID() {
        let state = StreamingMessageState()

        state.setToolCalls([ToolCall(id: "call_1", name: "exa__search", arguments: [:])])
        state.upsertToolResult(
            ToolResult(toolCallID: "call_2", toolName: "exa__search", content: "ignored", isError: true)
        )

        XCTAssertEqual(state.toolResultsByCallID.count, 0)
        XCTAssertEqual(state.renderTick, 1)
    }
}
