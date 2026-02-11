import XCTest
@testable import Jin

final class OpenAIChatCompletionsSourcesTests: XCTestCase {
    func testNonStreamingAppendsCitationsAsSourcesMarkdown() async throws {
        let payload: [String: Any] = [
            "id": "cmpl_sources_1",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "Answer"
                    ]
                ]
            ],
            "citations": [
                "https://example.com/a",
                "https://example.com/b"
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
        XCTAssertEqual(id, "cmpl_sources_1")

        guard case .contentDelta(.text(let content)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "Answer")

        guard case .contentDelta(.text(let sources)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(
            sources,
            "\n\n---\n\n### Sources\n1. <https://example.com/a>\n2. <https://example.com/b>"
        )

        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testNonStreamingPrefersSearchResultsOverCitations() async throws {
        let payload: [String: Any] = [
            "id": "cmpl_sources_2",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "Answer"
                    ]
                ]
            ],
            "citations": [
                "https://foo.com",
                "https://bar.com"
            ],
            "search_results": [
                [
                    "title": "Foo",
                    "url": "https://foo.com",
                    "snippet": "Foo snippet"
                ],
                [
                    "title": "Bar",
                    "url": "https://bar.com",
                    "snippet": "Bar snippet"
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

        guard case .contentDelta(.text(let sources)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(
            sources,
            "\n\n---\n\n### Sources\n1. [Foo](<https://foo.com>) — Foo snippet\n2. [Bar](<https://bar.com>) — Bar snippet"
        )
    }

    func testStreamingAppendsCitationsOnDone() async throws {
        let sseStream = AsyncThrowingStream<SSEEvent, Error> { continuation in
            let chunk1: [String: Any] = [
                "id": "cmpl_sources_3",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "content": "Answer"
                        ]
                    ]
                ]
            ]

            let chunk2: [String: Any] = [
                "id": "cmpl_sources_3",
                "citations": [
                    "https://example.com/a"
                ],
                "choices": [
                    [
                        "index": 0,
                        "delta": [:]
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

        XCTAssertEqual(events.count, 4)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_sources_3")

        guard case .contentDelta(.text(let content)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "Answer")

        guard case .contentDelta(.text(let sources)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(sources, "\n\n---\n\n### Sources\n1. <https://example.com/a>")

        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }
}
