import XCTest
@testable import Jin

final class AnthropicToolUseNormalizerTests: XCTestCase {
    func testStripsThinkingBlocksFromNonToolAssistantMessages() throws {
        let input: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "secret", signature: "sig")),
                .text("visible")
            ]),
        ]

        let normalized = AnthropicToolUseNormalizer.normalize(input)
        XCTAssertEqual(normalized.count, 2)

        let assistant = normalized[1]
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content.count, 1)
        if case .text(let text) = assistant.content[0] {
            XCTAssertEqual(text, "visible")
        } else {
            XCTFail("Expected text block after stripping thinking blocks")
        }
    }

    func testStripsThinkingBlocksForToolAssistantMessages() throws {
        let toolCall = ToolCall(id: "toolu_123", name: "mcp__foo", arguments: [:])
        let input: [Message] = [
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "secret", signature: "sig")),
                .text("visible")
            ], toolCalls: [toolCall]),
        ]

        let normalized = AnthropicToolUseNormalizer.normalize(input)
        XCTAssertEqual(normalized.count, 2) // assistant + synthetic tool msg

        let assistant = normalized[0]
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content.count, 1)
        if case .text(let text) = assistant.content[0] {
            XCTAssertEqual(text, "visible")
        } else {
            XCTFail("Expected text block after stripping thinking blocks")
        }
    }

    func testInsertsToolResultMessageWhenMissing() throws {
        let toolCall = ToolCall(
            id: "toolu_123",
            name: "exa__search",
            arguments: ["q": AnyCodable("hello")]
        )

        let input: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [.text("I'll call a tool")], toolCalls: [toolCall]),
            Message(role: .assistant, content: [.text("post-tool response")])
        ]

        let normalized = AnthropicToolUseNormalizer.normalize(input)

        XCTAssertEqual(normalized.count, 4)
        XCTAssertEqual(normalized[1].role, .assistant)
        XCTAssertEqual(normalized[2].role, .tool)

        let results = normalized[2].toolResults ?? []
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolCallID, "toolu_123")
        XCTAssertTrue(results[0].isError)
    }

    func testMovesExistingToolResultsAfterToolUse() throws {
        let toolCall = ToolCall(
            id: "toolu_abc",
            name: "exa__search",
            arguments: ["q": AnyCodable("hello")]
        )

        let existingResult = ToolResult(
            toolCallID: "toolu_abc",
            toolName: "exa__search",
            content: "world",
            isError: false
        )

        // Bad ordering: tool results appear before the assistant tool_use.
        let input: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .tool, content: [.text("ignored")], toolResults: [existingResult]),
            Message(role: .assistant, content: [], toolCalls: [toolCall]),
            Message(role: .assistant, content: [.text("done")])
        ]

        let normalized = AnthropicToolUseNormalizer.normalize(input)

        // Tool message should not appear before the tool_use after normalization.
        XCTAssertEqual(normalized[0].role, .user)
        XCTAssertEqual(normalized[1].role, .assistant)
        XCTAssertEqual(normalized[2].role, .tool)

        let results = normalized[2].toolResults ?? []
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolCallID, "toolu_abc")
        XCTAssertEqual(results[0].content, "world")
        XCTAssertFalse(results[0].isError)
    }

    func testStripsToolResultsFromUserMessages() throws {
        let stray = ToolResult(toolCallID: "toolu_stray", content: "oops", isError: true)
        let input: [Message] = [
            Message(role: .user, content: [.text("hi")], toolResults: [stray]),
        ]

        let normalized = AnthropicToolUseNormalizer.normalize(input)
        XCTAssertEqual(normalized.count, 1)
        XCTAssertNil(normalized[0].toolResults)
    }
}
