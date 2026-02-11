import XCTest
@testable import Jin

final class OpenAIChatCompletionsThinkTagTests: XCTestCase {
    func testNonStreamingSplitsLeadingThinkTagsIntoThinkingAndVisible() async throws {
        let payload: [String: Any] = [
            "id": "cmpl_1",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "<think>reason</think>\nAnswer"
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try OpenAIChatCompletionsCore.decodeResponse(data)
        let stream = OpenAIChatCompletionsCore.makeNonStreamingStream(
            response: response,
            reasoningField: .reasoningOrReasoningContent
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_1")

        guard case .thinkingDelta(.thinking(let thinking, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(thinking, "reason")

        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "\nAnswer")
        XCTAssertFalse(content.contains("<think>"))

        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testStreamingSplitsThinkTagsAcrossChunks() async throws {
        let sseStream = AsyncThrowingStream<SSEEvent, Error> { continuation in
            let chunk1: [String: Any] = [
                "id": "cmpl_2",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "content": "<think>rea"
                        ]
                    ]
                ]
            ]
            let chunk2: [String: Any] = [
                "id": "cmpl_2",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "content": "son</think>\nAnswer"
                        ]
                    ]
                ]
            ]

            do {
                let data1 = try JSONSerialization.data(withJSONObject: chunk1)
                let data2 = try JSONSerialization.data(withJSONObject: chunk2)
                continuation.yield(.event(type: "message", data: String(decoding: data1, as: UTF8.self)))
                continuation.yield(.event(type: "message", data: String(decoding: data2, as: UTF8.self)))
                continuation.yield(.done)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        let stream = OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoningOrReasoningContent
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 5)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_2")

        guard case .thinkingDelta(.thinking(let t1, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(t1, "rea")

        guard case .thinkingDelta(.thinking(let t2, _)) = events[2] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(t2, "son")

        guard case .contentDelta(.text(let content)) = events[3] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "\nAnswer")
        XCTAssertFalse(content.contains("<think>"))
        XCTAssertFalse(content.contains("</think>"))

        guard case .messageEnd = events[4] else { return XCTFail("Expected messageEnd") }
    }
}
