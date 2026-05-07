import XCTest
@testable import Jin

final class XAIVideoPollingSupportTests: XCTestCase {
    func testClassifiesKnownStatusAliases() {
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("done"), .done)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("complete"), .done)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("completed"), .done)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("success"), .done)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("expired"), .expired)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("failed", failureMessage: "bad input"), .failed("bad input"))
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("error"), .failed(nil))
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("pending"), .pending)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("in_progress"), .pending)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("processing"), .pending)
        XCTAssertEqual(XAIVideoPollingSupport.classifyStatusString("queued"), .pending)
        XCTAssertNil(XAIVideoPollingSupport.classifyStatusString("unknown"))
    }

    func testResolveStatusPrefersCodableThenRawStatusThenHTTPStatus() throws {
        let codableDone = try decodeStatusResponse(["status": "completed"])
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: codableDone, rawJSON: nil, httpStatus: 200),
            .done
        )

        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(
                codable: nil,
                rawJSON: ["state": "failed", "error": ["message": "bad source"]],
                httpStatus: 200
            ),
            .failed("bad source")
        )

        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: nil, rawJSON: nil, httpStatus: 404),
            .expired
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: nil, rawJSON: nil, httpStatus: 410),
            .expired
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: nil, rawJSON: nil, httpStatus: 503),
            .failed("Server error (HTTP 503)")
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: nil, rawJSON: nil, httpStatus: 429),
            .failed("HTTP 429")
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(codable: nil, rawJSON: nil, httpStatus: 200),
            .pending
        )
    }

    func testResolveStatusTreatsRawVideoURLAsDone() {
        XCTAssertEqual(
            XAIVideoPollingSupport.resolveStatus(
                codable: nil,
                rawJSON: ["result": ["url": "https://vidgen.example.com/fallback-done.mp4"]],
                httpStatus: 200
            ),
            .done
        )
    }

    func testExtractFailureMessageChecksNestedShapes() {
        XCTAssertEqual(
            XAIVideoPollingSupport.extractFailureMessage(from: ["message": " top level "]),
            "top level"
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.extractFailureMessage(from: ["error": " inline error "]),
            "inline error"
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.extractFailureMessage(from: ["error": ["detail": "nested detail"]]),
            "nested detail"
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.extractFailureMessage(from: ["errors": [["message": "array message"]]]),
            "array message"
        )
        XCTAssertEqual(
            XAIVideoPollingSupport.extractFailureMessage(from: ["result": ["message": "result message"]]),
            "result message"
        )
        XCTAssertNil(XAIVideoPollingSupport.extractFailureMessage(from: ["message": "   "]))
    }

    func testExtractVideoURLChecksCodableAndRawFallbackShapes() throws {
        let codable = try decodeStatusResponse(["video": ["url": "https://example.com/codable.mp4", "duration": 5]])
        XCTAssertEqual(
            XAIVideoPollingSupport.extractVideoURL(codable: codable, rawJSON: nil)?.absoluteString,
            "https://example.com/codable.mp4"
        )

        let rawCases: [([String: Any], String)] = [
            (["video": ["url": "https://example.com/video.mp4"]], "https://example.com/video.mp4"),
            (["response": ["video": ["url": "https://example.com/response-video.mp4"]]], "https://example.com/response-video.mp4"),
            (["result": ["video": ["url": "https://example.com/result-video.mp4"]]], "https://example.com/result-video.mp4"),
            (["result": ["url": "https://example.com/result-url"]], "https://example.com/result-url"),
            (["data": ["video": ["url": "https://example.com/data-video.mp4"]]], "https://example.com/data-video.mp4"),
            (["url": "https://vidgen.example.com/output"], "https://vidgen.example.com/output"),
            (["url": "https://example.com/output.mp4"], "https://example.com/output.mp4"),
            (["url": "https://example.com/video/output"], "https://example.com/video/output"),
        ]

        for (json, expected) in rawCases {
            XCTAssertEqual(
                XAIVideoPollingSupport.extractVideoURL(codable: nil, rawJSON: json)?.absoluteString,
                expected
            )
        }

        XCTAssertNil(
            XAIVideoPollingSupport.extractVideoURL(
                codable: nil,
                rawJSON: ["url": "https://example.com/plain-download"]
            )
        )
    }

    func testTrackDecodeFailuresOnlyCountsUndecodableSuccessfulResponsesWithoutStatusSignal() throws {
        XCTAssertEqual(
            try XAIVideoPollingSupport.trackDecodeFailures(
                statusResponse: nil,
                rawJSON: ["status": "pending"],
                httpStatus: 200,
                rawBody: "{}",
                consecutiveFailures: 3,
                maxFailures: 5
            ),
            0
        )

        let codable = try decodeStatusResponse(["status": "pending"])
        XCTAssertEqual(
            try XAIVideoPollingSupport.trackDecodeFailures(
                statusResponse: codable,
                rawJSON: nil,
                httpStatus: 200,
                rawBody: "{}",
                consecutiveFailures: 3,
                maxFailures: 5
            ),
            0
        )

        XCTAssertEqual(
            try XAIVideoPollingSupport.trackDecodeFailures(
                statusResponse: nil,
                rawJSON: nil,
                httpStatus: 500,
                rawBody: "{}",
                consecutiveFailures: 3,
                maxFailures: 5
            ),
            0
        )

        XCTAssertEqual(
            try XAIVideoPollingSupport.trackDecodeFailures(
                statusResponse: nil,
                rawJSON: ["details": ["phase": "working"]],
                httpStatus: 200,
                rawBody: "{\"details\":{\"phase\":\"working\"}}",
                consecutiveFailures: 3,
                maxFailures: 5
            ),
            4
        )
    }

    func testTrackDecodeFailuresThrowsAtLimitWithTruncatedBody() {
        XCTAssertThrowsError(
            try XAIVideoPollingSupport.trackDecodeFailures(
                statusResponse: nil,
                rawJSON: ["details": ["marker": "poll_6"]],
                httpStatus: 200,
                rawBody: #"{"details":{"marker":"poll_6"}}"#,
                consecutiveFailures: 4,
                maxFailures: 5
            )
        ) { error in
            guard case .decodingError(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.decodingError, got \(error)")
            }
            XCTAssertTrue(message.contains("5 consecutive attempts"))
            XCTAssertTrue(message.contains("poll_6"))
        }
    }

    private func decodeStatusResponse(_ json: [String: Any]) throws -> XAIVideoStatusResponse {
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XAIVideoStatusResponse.self, from: data)
    }
}
