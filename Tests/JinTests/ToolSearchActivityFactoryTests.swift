import XCTest
@testable import Jin

final class ToolSearchActivityFactoryTests: XCTestCase {
    func testNormalizedToolResultContentTrimsOutputAndUsesFallbacks() {
        XCTAssertEqual(
            ToolSearchActivityFactory.normalizedToolResultContent(
                "  Found result\n",
                toolName: "web_search",
                isError: false
            ),
            "Found result"
        )
        XCTAssertEqual(
            ToolSearchActivityFactory.normalizedToolResultContent(
                " \n ",
                toolName: "web_search",
                isError: false
            ),
            "Tool web_search returned no output"
        )
        XCTAssertEqual(
            ToolSearchActivityFactory.normalizedToolResultContent(
                "",
                toolName: "web_search",
                isError: true
            ),
            "Tool web_search failed without details"
        )
    }

    func testActivityForToolCallStartTrimsQueryAndAppliesProviderOverride() throws {
        let activity = try XCTUnwrap(
            ToolSearchActivityFactory.activityForToolCallStart(
                call: ToolCall(
                    id: "call_1",
                    name: "web_search",
                    arguments: ["query": AnyCodable("  SwiftUI updates  ")]
                ),
                providerOverride: .exa
            )
        )

        XCTAssertEqual(activity.id, "tool-search-call_1")
        XCTAssertEqual(activity.status, .searching)
        XCTAssertEqual(activity.arguments["query"]?.value as? String, "SwiftUI updates")
        XCTAssertEqual(activity.arguments["provider"]?.value as? String, SearchPluginProvider.exa.rawValue)
    }

    func testActivityForToolCallStartDropsBlankQueryAndSkipsNonSearchTools() throws {
        let searchActivity = try XCTUnwrap(
            ToolSearchActivityFactory.activityForToolCallStart(
                call: ToolCall(
                    id: "call_1",
                    name: "web_lookup",
                    arguments: ["q": AnyCodable(" \n ")]
                ),
                providerOverride: nil
            )
        )

        XCTAssertNil(searchActivity.arguments["query"])
        XCTAssertNil(
            ToolSearchActivityFactory.activityForToolCallStart(
                call: ToolCall(id: "call_2", name: "read_file", arguments: [:]),
                providerOverride: nil
            )
        )
    }
}
