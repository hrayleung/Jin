import XCTest
@testable import Jin

final class StreamingUIFlushBufferTests: XCTestCase {
    func testCurrentFlushIntervalUsesStreamedCharacterThresholds() {
        var buffer = StreamingUIFlushBuffer()
        XCTAssertEqual(buffer.currentFlushInterval, 0.08, accuracy: 0.0001)

        buffer.appendText(String(repeating: "a", count: 4_000))
        XCTAssertEqual(buffer.currentFlushInterval, 0.10, accuracy: 0.0001)

        buffer.appendThinking(String(repeating: "b", count: 8_000))
        XCTAssertEqual(buffer.currentFlushInterval, 0.12, accuracy: 0.0001)
    }

    func testNonForcedFlushRequiresElapsedIntervalAndPendingDeltas() throws {
        var buffer = StreamingUIFlushBuffer()

        XCTAssertNil(buffer.flushIfNeeded(now: 1.0))

        buffer.appendText("hello")
        XCTAssertNil(buffer.flushIfNeeded(now: 0.079))

        let flush = try XCTUnwrap(buffer.flushIfNeeded(now: 0.08))
        XCTAssertEqual(flush.textDelta, "hello")
        XCTAssertEqual(flush.thinkingDelta, "")
        XCTAssertTrue(flush.isFirstFlush)
        XCTAssertFalse(flush.force)
    }

    func testFlushClearsPendingDeltasAndPreservesStreamedCharacterCount() throws {
        var buffer = StreamingUIFlushBuffer()
        buffer.appendText("hello")
        buffer.appendThinking("world")

        let firstFlush = try XCTUnwrap(buffer.flushIfNeeded(now: 0.08))
        XCTAssertEqual(firstFlush.textDelta, "hello")
        XCTAssertEqual(firstFlush.thinkingDelta, "world")
        XCTAssertEqual(buffer.streamedCharacterCount, 10)

        buffer.appendText(String(repeating: "a", count: 3_990))
        XCTAssertEqual(buffer.streamedCharacterCount, 4_000)
        XCTAssertNil(buffer.flushIfNeeded(now: 0.179))

        let secondFlush = try XCTUnwrap(buffer.flushIfNeeded(now: 0.181))
        XCTAssertEqual(secondFlush.textDelta, String(repeating: "a", count: 3_990))
        XCTAssertEqual(secondFlush.thinkingDelta, "")
        XCTAssertFalse(secondFlush.isFirstFlush)
        XCTAssertEqual(buffer.currentFlushInterval, 0.10, accuracy: 0.0001)
    }

    func testForcedFlushEmitsEvenWithoutPendingDeltas() throws {
        var buffer = StreamingUIFlushBuffer()

        let flush = try XCTUnwrap(buffer.flushIfNeeded(force: true, now: 0))
        XCTAssertEqual(flush.textDelta, "")
        XCTAssertEqual(flush.thinkingDelta, "")
        XCTAssertNil(flush.toolCalls)
        XCTAssertTrue(flush.searchActivities.isEmpty)
        XCTAssertTrue(flush.codeExecutionActivities.isEmpty)
        XCTAssertTrue(flush.isFirstFlush)
        XCTAssertTrue(flush.force)

        let secondFlush = try XCTUnwrap(buffer.flushIfNeeded(force: true, now: 0.01))
        XCTAssertFalse(secondFlush.isFirstFlush)
        XCTAssertNil(secondFlush.toolCalls)
        XCTAssertTrue(secondFlush.searchActivities.isEmpty)
        XCTAssertTrue(secondFlush.codeExecutionActivities.isEmpty)
    }

    func testFirstActivityFlushEmitsImmediatelyAndLaterActivityWaitsForInterval() throws {
        var buffer = StreamingUIFlushBuffer()
        buffer.setToolCalls([
            ToolCall(id: "call_1", name: "exa__search", arguments: [:])
        ])

        let firstFlush = try XCTUnwrap(buffer.flushIfNeeded(now: 0))
        XCTAssertEqual(firstFlush.textDelta, "")
        XCTAssertEqual(firstFlush.thinkingDelta, "")
        XCTAssertEqual(firstFlush.toolCalls?.map(\.id), ["call_1"])
        XCTAssertTrue(firstFlush.searchActivities.isEmpty)
        XCTAssertTrue(firstFlush.isFirstFlush)
        XCTAssertFalse(firstFlush.force)

        buffer.setToolCalls([
            ToolCall(id: "call_1", name: "exa__search", arguments: ["q": AnyCodable("x")]),
            ToolCall(id: "call_2", name: "exa__search", arguments: [:])
        ])
        buffer.upsertSearchActivity(
            SearchActivity(id: "ws_1", type: "search", status: .inProgress)
        )
        XCTAssertNil(buffer.flushIfNeeded(now: 0.079))

        let secondFlush = try XCTUnwrap(buffer.flushIfNeeded(now: 0.08))
        XCTAssertEqual(secondFlush.toolCalls?.map(\.id), ["call_1", "call_2"])
        XCTAssertEqual(secondFlush.searchActivities.map(\.id), ["ws_1"])
        XCTAssertFalse(secondFlush.isFirstFlush)
    }

    func testFirstActivityStillFlushesImmediatelyAfterForcedEmptyFlush() throws {
        var buffer = StreamingUIFlushBuffer()
        _ = buffer.flushIfNeeded(force: true, now: 0)

        buffer.setToolCalls([
            ToolCall(id: "call_1", name: "exa__search", arguments: [:])
        ])
        let flush = try XCTUnwrap(buffer.flushIfNeeded(now: 0.01))
        XCTAssertEqual(flush.toolCalls?.map(\.id), ["call_1"])
        XCTAssertFalse(flush.isFirstFlush)
    }

    func testToolCallsAndTextFlushTogether() throws {
        var buffer = StreamingUIFlushBuffer()
        buffer.appendText("hello")
        buffer.appendThinking("reason")
        buffer.setToolCalls([
            ToolCall(id: "call_1", name: "exa__search", arguments: [:])
        ])

        let flush = try XCTUnwrap(buffer.flushIfNeeded(now: 0))
        XCTAssertEqual(flush.textDelta, "hello")
        XCTAssertEqual(flush.thinkingDelta, "reason")
        XCTAssertEqual(flush.toolCalls?.map(\.id), ["call_1"])
        XCTAssertTrue(flush.isFirstFlush)
        XCTAssertEqual(buffer.streamedCharacterCount, 11)
    }

    func testSearchUpsertsMergeByIDAcrossPendingWindow() throws {
        var buffer = StreamingUIFlushBuffer()
        buffer.upsertSearchActivity(
            SearchActivity(
                id: "ws_1",
                type: "search",
                status: .inProgress,
                arguments: ["query": AnyCodable("swift")]
            )
        )
        buffer.upsertSearchActivity(
            SearchActivity(
                id: "ws_1",
                type: "search",
                status: .completed,
                arguments: ["url": AnyCodable("https://example.com")]
            )
        )
        buffer.upsertSearchActivity(
            SearchActivity(
                id: "ws_2",
                type: "open_page",
                status: .inProgress
            )
        )

        let flush = try XCTUnwrap(buffer.flushIfNeeded(now: 0))
        XCTAssertEqual(flush.searchActivities.count, 2)
        XCTAssertEqual(flush.searchActivities[0].id, "ws_1")
        XCTAssertEqual(flush.searchActivities[0].status, .completed)
        XCTAssertEqual(flush.searchActivities[0].arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(flush.searchActivities[0].arguments["url"]?.value as? String, "https://example.com")
        XCTAssertEqual(flush.searchActivities[1].id, "ws_2")
        XCTAssertEqual(flush.searchActivities[1].type, "open_page")
        XCTAssertNil(flush.toolCalls)
        XCTAssertTrue(flush.codeExecutionActivities.isEmpty)
    }

    func testCodeExecutionUpsertsMergeByIDAcrossPendingWindow() throws {
        var buffer = StreamingUIFlushBuffer()
        buffer.upsertCodeExecutionActivity(
            CodeExecutionActivity(id: "ce_1", status: .writingCode, code: "print(")
        )
        buffer.upsertCodeExecutionActivity(
            CodeExecutionActivity(id: "ce_1", status: .completed, code: "print(1)", stdout: "1")
        )

        let flush = try XCTUnwrap(buffer.flushIfNeeded(now: 0))
        XCTAssertEqual(flush.codeExecutionActivities.count, 1)
        XCTAssertEqual(flush.codeExecutionActivities[0].id, "ce_1")
        XCTAssertEqual(flush.codeExecutionActivities[0].status, .completed)
        XCTAssertEqual(flush.codeExecutionActivities[0].code, "print(1)")
        XCTAssertEqual(flush.codeExecutionActivities[0].stdout, "1")
    }

    func testActivityPayloadsDoNotIncreaseStreamedCharacterCount() {
        var buffer = StreamingUIFlushBuffer()
        buffer.setToolCalls([
            ToolCall(id: "call_1", name: "exa__search", arguments: [:])
        ])
        buffer.upsertSearchActivity(
            SearchActivity(id: "ws_1", type: "search", status: .inProgress)
        )
        buffer.upsertCodeExecutionActivity(
            CodeExecutionActivity(id: "ce_1", status: .inProgress, code: "print(1)")
        )

        XCTAssertEqual(buffer.streamedCharacterCount, 0)
        XCTAssertEqual(buffer.currentFlushInterval, 0.08, accuracy: 0.0001)
    }
}
