import XCTest
@testable import Jin

final class AnthropicRequestPreflightTests: XCTestCase {
    func testValidToolUseSequencePasses() throws {
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [["type": "text", "text": "hi"]]
            ],
            [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "I'll call a tool"],
                    ["type": "tool_use", "id": "toolu_123", "name": "mcp__foo", "input": ["q": "hello"]]
                ]
            ],
            [
                "role": "user",
                "content": [
                    ["type": "tool_result", "tool_use_id": "toolu_123", "content": "world", "is_error": false]
                ]
            ]
        ]

        XCTAssertNoThrow(try AnthropicRequestPreflight.validate(messages: messages))
    }

    func testMissingToolResultImmediatelyAfterToolUseFails() throws {
        let messages: [[String: Any]] = [
            [
                "role": "assistant",
                "content": [
                    ["type": "tool_use", "id": "toolu_1", "name": "mcp__foo", "input": [:]]
                ]
            ],
            [
                "role": "user",
                "content": [["type": "text", "text": "not a tool result"]]
            ]
        ]

        XCTAssertThrowsError(try AnthropicRequestPreflight.validate(messages: messages))
    }

    func testToolResultNotFirstInUserMessageFails() throws {
        let messages: [[String: Any]] = [
            [
                "role": "assistant",
                "content": [
                    ["type": "tool_use", "id": "toolu_1", "name": "mcp__foo", "input": [:]]
                ]
            ],
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": "oops"],
                    ["type": "tool_result", "tool_use_id": "toolu_1", "content": "ok", "is_error": false]
                ]
            ]
        ]

        XCTAssertThrowsError(try AnthropicRequestPreflight.validate(messages: messages))
    }

    func testToolResultInLaterUserMessageFails() throws {
        let messages: [[String: Any]] = [
            [
                "role": "assistant",
                "content": [
                    ["type": "tool_use", "id": "toolu_1", "name": "mcp__foo", "input": [:]]
                ]
            ],
            [
                "role": "user",
                "content": [["type": "text", "text": "intervening user message"]]
            ],
            [
                "role": "user",
                "content": [
                    ["type": "tool_result", "tool_use_id": "toolu_1", "content": "ok", "is_error": false]
                ]
            ]
        ]

        XCTAssertThrowsError(try AnthropicRequestPreflight.validate(messages: messages))
    }
}

