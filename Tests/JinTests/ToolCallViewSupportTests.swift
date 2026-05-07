import XCTest
@testable import Jin

final class ToolCallViewSupportTests: XCTestCase {
    func testFormattedArgumentsJSONPrettyPrintsSortedKeysAndAllowsEmptyObject() {
        XCTAssertEqual(
            ToolCallViewSupport.formattedArgumentsJSON(
                for: [
                    "zeta": AnyCodable(2),
                    "alpha": AnyCodable("one")
                ]
            ),
            """
            {
              "alpha" : "one",
              "zeta" : 2
            }
            """
        )
        XCTAssertEqual(
            ToolCallViewSupport.formattedArgumentsJSON(for: [:]),
            "{\n\n}"
        )
    }

    func testFormattedArgumentsJSONReturnsNilForInvalidJSONObject() {
        XCTAssertNil(ToolCallViewSupport.formattedArgumentsJSON(for: ["bad": AnyCodable(Double.nan)]))
    }

    func testParseFunctionNameHandlesServerPrefixAndFallbacks() {
        XCTAssertEqual(
            ToolCallViewSupport.parseFunctionName("github__search"),
            .init(serverID: "github", toolName: "search")
        )
        XCTAssertEqual(
            ToolCallViewSupport.parseFunctionName("search"),
            .init(serverID: "", toolName: "search")
        )
        XCTAssertEqual(
            ToolCallViewSupport.parseFunctionName("github__"),
            .init(serverID: "github", toolName: "github__")
        )
        XCTAssertEqual(
            ToolCallViewSupport.parseFunctionName("__search"),
            .init(serverID: "", toolName: "search")
        )
    }

    func testServerLabelFallsBackToMCPForEmptyServerID() {
        XCTAssertEqual(
            ToolCallViewSupport.serverLabel(for: .init(serverID: "", toolName: "search")),
            "mcp"
        )
        XCTAssertEqual(
            ToolCallViewSupport.serverLabel(for: .init(serverID: " \n ", toolName: "search")),
            "mcp"
        )
        XCTAssertEqual(
            ToolCallViewSupport.serverLabel(for: .init(serverID: "github", toolName: "search")),
            "github"
        )
        XCTAssertEqual(
            ToolCallViewSupport.serverLabel(for: .init(serverID: " github ", toolName: "search")),
            "github"
        )
    }

    func testDurationTextMatchesExistingRoundingBehavior() {
        XCTAssertNil(ToolCallViewSupport.durationText(for: nil))
        XCTAssertNil(ToolCallViewSupport.durationText(for: 0))
        XCTAssertNil(ToolCallViewSupport.durationText(for: -0.1))
        XCTAssertEqual(ToolCallViewSupport.durationText(for: 0.244), "244ms")
        XCTAssertEqual(ToolCallViewSupport.durationText(for: 0.5), "500ms")
        XCTAssertEqual(ToolCallViewSupport.durationText(for: 1.49), "1s")
        XCTAssertEqual(ToolCallViewSupport.durationText(for: 1.5), "2s")
    }

    func testExecutionStatusMapsMissingAndResultErrorState() {
        XCTAssertEqual(ToolCallViewSupport.executionStatus(for: nil), .running)
        XCTAssertEqual(
            ToolCallViewSupport.executionStatus(for: toolResult(isError: false)),
            .success
        )
        XCTAssertEqual(
            ToolCallViewSupport.executionStatus(for: toolResult(isError: true)),
            .error
        )
    }

    func testExecutionStatusMapsToTerminalTimelineNodeGlyphs() {
        XCTAssertEqual(ToolTimelinePresentationSupport.TerminalStatusNodeGlyph(status: .running), .running)
        XCTAssertEqual(ToolTimelinePresentationSupport.TerminalStatusNodeGlyph(status: .success), .success)
        XCTAssertEqual(ToolTimelinePresentationSupport.TerminalStatusNodeGlyph(status: .error), .error)
    }

    func testArgumentSummaryUsesPreferredKeysAndCondensesWhitespace() {
        XCTAssertEqual(
            ToolCallViewSupport.argumentSummary(
                for: [
                    "ignored": AnyCodable("skip"),
                    "query": AnyCodable("  find this\nnow  ")
                ]
            ),
            "find this now"
        )
    }

    func testArgumentSummarySkipsBlankPreferredValues() {
        XCTAssertEqual(
            ToolCallViewSupport.argumentSummary(
                for: [
                    "query": AnyCodable(" \n "),
                    "url": AnyCodable(" https://example.com/page ")
                ]
            ),
            "https://example.com/page"
        )
    }

    func testArgumentSummaryFallsBackToJSONWhenPreferredValuesAreBlank() {
        XCTAssertEqual(
            ToolCallViewSupport.argumentSummary(
                for: [
                    "query": AnyCodable(" \n "),
                    "limit": AnyCodable(5)
                ]
            ),
            "{\"limit\":5,\"query\":\" \\n \"}"
        )
    }

    func testArgumentSummaryFallsBackToCompactSortedJSON() {
        XCTAssertEqual(
            ToolCallViewSupport.argumentSummary(
                for: [
                    "zeta": AnyCodable(2),
                    "alpha": AnyCodable("one")
                ]
            ),
            "{\"alpha\":\"one\",\"zeta\":2}"
        )
    }

    func testArgumentSummaryReturnsNilForEmptyOrInvalidJSONObject() {
        XCTAssertNil(ToolCallViewSupport.argumentSummary(for: [:]))
        XCTAssertNil(ToolCallViewSupport.argumentSummary(for: ["bad": AnyCodable(Double.nan)]))
    }

    func testArgumentSummaryTruncatesLongValues() {
        XCTAssertEqual(
            ToolCallViewSupport.argumentSummary(
                for: ["text": AnyCodable(String(repeating: "a", count: 10))],
                maxLength: 8
            ),
            "aaaaa..."
        )
    }

    func testStatusLabelsMatchToolCallCopy() {
        XCTAssertEqual(ToolCallViewSupport.statusLabel(for: .running), "Running")
        XCTAssertEqual(ToolCallViewSupport.statusLabel(for: .success), "Done")
        XCTAssertEqual(ToolCallViewSupport.statusLabel(for: .error), "Failed")
    }

    func testOneLineCondensesWhitespaceAndTruncates() {
        XCTAssertEqual(ToolCallViewSupport.oneLine("  one\n two\tthree  ", maxLength: 20), "one two three")
        XCTAssertEqual(ToolCallViewSupport.oneLine("abcdef", maxLength: 5), "ab...")
    }

    private func toolResult(isError: Bool) -> ToolResult {
        ToolResult(
            toolCallID: "call",
            content: "",
            isError: isError
        )
    }
}
