import XCTest
@testable import Jin

final class MessageEntityResponseMetricsTests: XCTestCase {
    func testMessageEntityResponseMetricsRoundTrip() throws {
        let message = Message(role: .assistant, content: [.text("Hi")])
        let entity = try MessageEntity.fromDomain(message)

        let metrics = ResponseMetrics(
            usage: Usage(inputTokens: 88, outputTokens: 99, thinkingTokens: 7, cachedTokens: 3),
            timeToFirstTokenSeconds: 1.4,
            durationSeconds: 4.2
        )
        entity.responseMetrics = metrics

        XCTAssertNotNil(entity.responseMetricsData)
        XCTAssertEqual(entity.responseMetrics, metrics)
    }

    func testMessageEntityResponseMetricsCanBeCleared() throws {
        let message = Message(role: .assistant, content: [.text("Hi")])
        let entity = try MessageEntity.fromDomain(message)

        entity.responseMetrics = ResponseMetrics(
            usage: Usage(inputTokens: 1, outputTokens: 2),
            timeToFirstTokenSeconds: 0.2,
            durationSeconds: 1.5
        )
        entity.responseMetrics = nil

        XCTAssertNil(entity.responseMetricsData)
        XCTAssertNil(entity.responseMetrics)
    }
}
