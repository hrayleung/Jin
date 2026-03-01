import XCTest
@testable import Jin

final class ResponseMetricsTests: XCTestCase {
    func testOutputTokensPerSecondWhenUsageAndDurationPresent() throws {
        let metrics = ResponseMetrics(
            usage: Usage(inputTokens: 100, outputTokens: 250),
            timeToFirstTokenSeconds: 1.2,
            durationSeconds: 5
        )

        let speed = try XCTUnwrap(metrics.outputTokensPerSecond)
        XCTAssertEqual(speed, 50, accuracy: 0.0001)
    }

    func testOutputTokensPerSecondIsNilWhenDurationMissingOrNonPositive() {
        let usage = Usage(inputTokens: 100, outputTokens: 250)

        let missingDuration = ResponseMetrics(
            usage: usage,
            timeToFirstTokenSeconds: 1.2,
            durationSeconds: nil
        )
        XCTAssertNil(missingDuration.outputTokensPerSecond)

        let zeroDuration = ResponseMetrics(
            usage: usage,
            timeToFirstTokenSeconds: 1.2,
            durationSeconds: 0
        )
        XCTAssertNil(zeroDuration.outputTokensPerSecond)
    }

    func testOutputTokensPerSecondIsNilWhenUsageMissing() {
        let metrics = ResponseMetrics(
            usage: nil,
            timeToFirstTokenSeconds: 1.2,
            durationSeconds: 4
        )

        XCTAssertNil(metrics.outputTokensPerSecond)
    }
}
