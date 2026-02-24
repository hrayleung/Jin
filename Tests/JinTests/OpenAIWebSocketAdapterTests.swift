import Foundation
import XCTest
@testable import Jin

final class OpenAIWebSocketAdapterTests: XCTestCase {
    func testResponseCreateEventPutsResponsesBodyAtTopLevel() throws {
        let responsePayload: [String: Any] = [
            "model": "gpt-5.2",
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "hi"]
                    ]
                ]
            ],
            "previous_response_id": "resp_prev_123"
        ]

        let event = OpenAIWebSocketAdapter.responseCreateEvent(from: responsePayload)

        XCTAssertEqual(event["type"] as? String, "response.create")
        XCTAssertEqual(event["model"] as? String, "gpt-5.2")
        XCTAssertNotNil(event["input"])
        XCTAssertNil(event["response"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: event))
    }

    func testDecodeErrorEventPayloadExtractsCodeAndMessage() throws {
        let json = """
        {"type":"error","error":{"code":"invalid_request_error","message":"Bad request"}}
        """

        let err = OpenAIWebSocketAdapter.decodeErrorEventPayload(
            Data(json.utf8),
            fallbackMessage: "fallback"
        )

        guard case .providerError(let code, let message) = err else {
            return XCTFail("Expected providerError")
        }

        XCTAssertEqual(code, "invalid_request_error")
        XCTAssertEqual(message, "Bad request")
    }

    func testDecodeErrorEventPayloadFallsBackToTypeAndOuterMessage() throws {
        let json = """
        {"type":"error","error":{"type":"rate_limit","message":"Too many requests"}}
        """

        let err = OpenAIWebSocketAdapter.decodeErrorEventPayload(
            Data(json.utf8),
            fallbackMessage: "fallback"
        )

        guard case .providerError(let code, let message) = err else {
            return XCTFail("Expected providerError")
        }

        XCTAssertEqual(code, "rate_limit")
        XCTAssertEqual(message, "Too many requests")
    }
}

