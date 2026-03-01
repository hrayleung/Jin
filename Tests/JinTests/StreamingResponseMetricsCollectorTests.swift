import XCTest
@testable import Jin

final class StreamingResponseMetricsCollectorTests: XCTestCase {
    func testCollectorCapturesTTFTFromFirstTextDelta() throws {
        var collector = StreamingResponseMetricsCollector()
        let start = Date(timeIntervalSince1970: 1_000)
        collector.begin(at: start)

        collector.observe(
            event: .contentDelta(.text("Hello")),
            at: start.addingTimeInterval(0.8)
        )
        collector.end(at: start.addingTimeInterval(2.0))

        let metrics = try XCTUnwrap(collector.metrics)
        XCTAssertEqual(try XCTUnwrap(metrics.timeToFirstTokenSeconds), 0.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(metrics.durationSeconds), 2.0, accuracy: 0.0001)
    }

    func testCollectorUsesFirstOutputBlockAcrossThinkingAndMedia() throws {
        var collector = StreamingResponseMetricsCollector()
        let start = Date(timeIntervalSince1970: 2_000)
        collector.begin(at: start)

        collector.observe(
            event: .thinkingDelta(.thinking(textDelta: "", signature: nil)),
            at: start.addingTimeInterval(0.2)
        )
        collector.observe(
            event: .contentDelta(.image(ImageContent(mimeType: "image/png", data: Data([0x01])))),
            at: start.addingTimeInterval(0.5)
        )
        collector.observe(
            event: .contentDelta(.text("later")),
            at: start.addingTimeInterval(1.2)
        )
        collector.end(at: start.addingTimeInterval(3.0))

        let metrics = try XCTUnwrap(collector.metrics)
        XCTAssertEqual(try XCTUnwrap(metrics.timeToFirstTokenSeconds), 0.5, accuracy: 0.0001)
    }

    func testCollectorCapturesUsageFromMessageEnd() {
        var collector = StreamingResponseMetricsCollector()
        let start = Date(timeIntervalSince1970: 3_000)
        collector.begin(at: start)

        let usage = Usage(inputTokens: 123, outputTokens: 456, thinkingTokens: 12, cachedTokens: 9)
        collector.observe(
            event: .messageEnd(usage: usage),
            at: start.addingTimeInterval(1.5)
        )
        collector.end(at: start.addingTimeInterval(2.5))

        XCTAssertEqual(collector.metrics?.usage, usage)
    }

    func testCollectorIgnoresEmptyMessageEndAndKeepsExistingUsage() {
        var collector = StreamingResponseMetricsCollector()
        let start = Date(timeIntervalSince1970: 4_000)
        collector.begin(at: start)

        let usage = Usage(inputTokens: 10, outputTokens: 20)
        collector.observe(event: .messageEnd(usage: usage), at: start.addingTimeInterval(0.9))
        collector.observe(event: .messageEnd(usage: nil), at: start.addingTimeInterval(1.1))
        collector.end(at: start.addingTimeInterval(2.0))

        XCTAssertEqual(collector.metrics?.usage, usage)
    }
}
