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
        XCTAssertTrue(flush.isFirstFlush)
        XCTAssertTrue(flush.force)

        let secondFlush = try XCTUnwrap(buffer.flushIfNeeded(force: true, now: 0.01))
        XCTAssertFalse(secondFlush.isFirstFlush)
    }
}
