import XCTest
import Combine
@testable import Jin

@MainActor
final class StreamingMessageStateTests: XCTestCase {
    func testAppendDeltasIncrementsRenderTickOnce() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "hello", thinkingDelta: "world")

        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(state.textContent, "hello")
        XCTAssertEqual(state.thinkingContent, "world")
        XCTAssertEqual(state.visibleText, "hello")
        XCTAssertEqual(state.visibleTextChunks, ["hello"])
        XCTAssertEqual(state.visibleTextCharacterCount, 5)
        XCTAssertTrue(state.artifacts.isEmpty)
    }

    func testAppendDeltasEmitsSingleObjectChange() {
        let state = StreamingMessageState()
        var changeCount = 0
        let cancellable = state.objectWillChange.sink {
            changeCount += 1
        }

        state.appendDeltas(textDelta: "hello", thinkingDelta: "world")

        XCTAssertEqual(changeCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testAppendDeltasTracksVisibleText() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "   \n\t", thinkingDelta: "")
        XCTAssertFalse(state.hasVisibleText)
        // Whitespace-only must not count as "visible" — StreamingMessageView
        // keeps the Generating placeholder until non-whitespace arrives.
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
        XCTAssertEqual(state.thinkingChunks, [])
        XCTAssertEqual(state.textContent, "")
        XCTAssertEqual(state.thinkingContent, "")
        XCTAssertEqual(state.visibleText, "")
        XCTAssertEqual(state.visibleTextChunks, [])
        XCTAssertEqual(state.visibleTextCharacterCount, 0)
        XCTAssertEqual(state.artifacts, [])
        XCTAssertEqual(state.streamingToolCalls.count, 0)
        XCTAssertEqual(state.toolResultsByCallID.count, 0)
        XCTAssertFalse(state.hasVisiblePresentation)
    }

    func testHasVisiblePresentationTracksToolsTextAndActivities() {
        let state = StreamingMessageState()
        XCTAssertFalse(state.hasVisiblePresentation)

        state.setToolCalls([
            ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:]),
        ])
        XCTAssertTrue(state.hasVisiblePresentation)

        state.reset()
        state.appendDeltas(textDelta: "hello", thinkingDelta: "")
        XCTAssertTrue(state.hasVisiblePresentation)
    }

    func testAppendDeltasCachesVisibleTextAndArtifactsForStreaming() {
        let state = StreamingMessageState()

        state.appendDeltas(
            textDelta: """
            Intro
            <jinArtifact artifact_id="demo" title="Demo" contentType="text/html">
            <div>Hello</div>
            </jinArtifact>
            """,
            thinkingDelta: ""
        )

        XCTAssertEqual(state.visibleText.trimmingCharacters(in: .whitespacesAndNewlines), "Intro")
        XCTAssertEqual(state.visibleTextChunks.count, 1)
        XCTAssertEqual(state.artifacts.count, 1)
        XCTAssertEqual(state.artifacts.first?.artifactID, "demo")
        XCTAssertTrue(state.hasVisibleText)
    }

    func testAppendDeltasHidesTrailingIncompleteArtifactFromVisibleText() {
        let state = StreamingMessageState()

        state.appendDeltas(
            textDelta: "Before<jinArtifact artifact_id=\"demo\" title=\"Demo\" contentType=\"text/html\"><div>",
            thinkingDelta: ""
        )

        XCTAssertEqual(state.visibleText, "Before")
        XCTAssertEqual(state.visibleTextChunks, ["Before"])
        XCTAssertTrue(state.artifacts.isEmpty)
        XCTAssertTrue(state.hasVisibleText)
    }

    func testAppendDeltasMaintainsVisibleTextChunksForLongPlainStream() {
        let state = StreamingMessageState()
        let firstChunk = String(repeating: "a", count: 2_048)
        let secondChunk = String(repeating: "b", count: 2_048)
        let tail = "done"

        state.appendDeltas(textDelta: firstChunk, thinkingDelta: "")
        state.appendDeltas(textDelta: secondChunk, thinkingDelta: "")
        state.appendDeltas(textDelta: tail, thinkingDelta: "")

        XCTAssertEqual(state.visibleText, firstChunk + secondChunk + tail)
        XCTAssertEqual(state.visibleTextCharacterCount, 4_100)
        XCTAssertEqual(state.visibleTextChunks, [firstChunk, secondChunk, tail])
        XCTAssertTrue(state.hasVisibleText)
    }

    func testAppendDeltasRebuildsVisibleTextChunksWhenArtifactMarkupBecomesHidden() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "Before <jinArt", thinkingDelta: "")
        XCTAssertEqual(state.visibleText, "Before <jinArt")

        state.appendDeltas(
            textDelta: "ifact artifact_id=\"demo\" title=\"Demo\" contentType=\"text/html\"><div>",
            thinkingDelta: ""
        )

        XCTAssertEqual(state.visibleText, "Before ")
        XCTAssertEqual(state.visibleTextChunks, ["Before "])
        XCTAssertEqual(state.visibleTextCharacterCount, 7)
        XCTAssertTrue(state.hasVisibleText)
    }

    func testAppendDeltasAppendsVisibleChunksAfterCompletedArtifact() {
        let state = StreamingMessageState()
        let prefix = "Intro "
        let artifact = "\(prefix)<jinArtifact artifact_id=\"demo\" title=\"Demo\" contentType=\"text/html\"><div></div></jinArtifact>"
        let tail = String(repeating: "x", count: 2_050)

        state.appendDeltas(textDelta: artifact, thinkingDelta: "")
        state.appendDeltas(textDelta: tail, thinkingDelta: "")

        XCTAssertEqual(state.visibleText, prefix + tail)
        XCTAssertEqual(state.artifacts.count, 1)
        XCTAssertEqual(state.visibleTextCharacterCount, state.visibleText.count)
        XCTAssertGreaterThan(state.visibleTextChunks.count, 1)
        XCTAssertLessThanOrEqual(state.visibleTextChunks.map(\.count).max() ?? 0, 2_048)
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
