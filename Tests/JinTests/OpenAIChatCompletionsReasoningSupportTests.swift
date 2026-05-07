import XCTest
@testable import Jin

final class OpenAIChatCompletionsReasoningSupportTests: XCTestCase {
    func testMessageReasoningRespectsFieldPreference() throws {
        let message = try decodedMessage([
            "role": "assistant",
            "content": "Answer",
            "reasoning": "Reasoning",
            "reasoning_content": "Reasoning content"
        ])

        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.messageReasoning(message, field: .reasoning),
            "Reasoning"
        )
        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.messageReasoning(message, field: .reasoningContent),
            "Reasoning content"
        )
        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.messageReasoning(message, field: .reasoningOrReasoningContent),
            "Reasoning"
        )
    }

    func testReasoningDetailsAreFlattenedWhenExplicitFieldsAreBlank() throws {
        let message = try decodedMessage([
            "role": "assistant",
            "content": "Answer",
            "reasoning": "   ",
            "reasoning_details": [
                [
                    "summary": "Summary"
                ],
                [
                    "content": [
                        "text": "Nested text",
                        "summary": "Nested summary"
                    ]
                ],
                [
                    "reasoning": [
                        [
                            "content": "Array content"
                        ]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.messageReasoning(message, field: .reasoning),
            "Summary\nNested text\nNested summary\nArray content"
        )
    }

    func testChunkChoiceReasoningUsesIncrementalSnapshots() throws {
        let firstChoice = try decodedChunkChoice(reasoningDetailsSummary: "Rea")
        let secondChoice = try decodedChunkChoice(reasoningDetailsSummary: "Reason")

        let first = try XCTUnwrap(
            OpenAIChatCompletionsReasoningSupport.chunkChoiceReasoning(
                firstChoice,
                field: .reasoningOrReasoningContent
            )
        )
        let second = try XCTUnwrap(
            OpenAIChatCompletionsReasoningSupport.chunkChoiceReasoning(
                secondChoice,
                field: .reasoningOrReasoningContent
            )
        )

        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.incrementalDelta(
                candidate: first,
                previousSnapshot: ""
            ),
            "Rea"
        )
        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.incrementalDelta(
                candidate: second,
                previousSnapshot: first
            ),
            "son"
        )
        XCTAssertEqual(
            OpenAIChatCompletionsReasoningSupport.incrementalDelta(
                candidate: second,
                previousSnapshot: second
            ),
            ""
        )
    }

    private func decodedMessage(
        _ message: [String: Any]
    ) throws -> OpenAIChatCompletionsResponse.AssistantMessage {
        let payload: [String: Any] = [
            "id": "cmpl_reasoning_support",
            "choices": [
                [
                    "message": message
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try OpenAIChatCompletionsCore.decodeResponse(data)
        return try XCTUnwrap(response.choices.single?.message)
    }

    private func decodedChunkChoice(reasoningDetailsSummary: String) throws -> OpenAIChatCompletionsChunk.Choice {
        let payload: [String: Any] = [
            "id": "cmpl_reasoning_support",
            "choices": [
                [
                    "index": 0,
                    "delta": [:],
                    "reasoning_details": [
                        [
                            "summary": reasoningDetailsSummary
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let chunk = try OpenAIChatCompletionsCore.decodeChunk(data)
        return try XCTUnwrap(chunk.choices.single)
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
