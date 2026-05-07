import XCTest
@testable import Jin

final class MCPToolTimelineSupportTests: XCTestCase {
    func testEntriesAttachResultsByCallIDAndMapStatus() {
        let calls = [
            toolCall(id: "first", name: "github__search"),
            toolCall(id: "second", name: "linear__list"),
            toolCall(id: "third", name: "filesystem__read")
        ]
        let results = [
            "first": toolResult(id: "result-1", callID: "first"),
            "second": toolResult(id: "result-2", callID: "second", isError: true)
        ]

        let entries = MCPToolTimelineSupport.entries(
            toolCalls: calls,
            toolResultsByCallID: results
        )

        XCTAssertEqual(entries.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(entries.map(\.status), [.success, .error, .running])
    }

    func testCountsAndDurationsIgnoreMissingResultsForDuration() {
        let entries = [
            entry(id: "first", result: toolResult(callID: "first", durationSeconds: 0.25)),
            entry(id: "second", result: toolResult(callID: "second", isError: true, durationSeconds: 1.75)),
            entry(id: "third", result: nil)
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.counts(for: entries),
            .init(running: 1, succeeded: 1, failed: 1)
        )
        XCTAssertEqual(MCPToolTimelineSupport.totalDurationSeconds(for: entries), 2.0)
        XCTAssertNil(MCPToolTimelineSupport.totalDurationSeconds(for: [entry(id: "running", result: nil)]))
    }

    func testParseFunctionNameHandlesServerPrefixAndFallbacks() {
        XCTAssertEqual(
            MCPToolTimelineSupport.parseFunctionName("github__search"),
            .init(serverID: "github", toolName: "search")
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.parseFunctionName("search"),
            .init(serverID: "", toolName: "search")
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.parseFunctionName("github__"),
            .init(serverID: "github", toolName: "github__")
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.parseFunctionName("__search"),
            .init(serverID: "", toolName: "search")
        )
    }

    func testServerIDsNormalizeEmptyServerAndKeepFirstSeenOrder() {
        let entries = [
            entry(id: "first", name: "github__search"),
            entry(id: "second", name: "search"),
            entry(id: "third", name: "__read"),
            entry(id: "fourth", name: "github__issues"),
            entry(id: "fifth", name: "linear__list")
        ]

        XCTAssertEqual(MCPToolTimelineSupport.serverIDs(for: entries), ["github", "mcp", "linear"])
    }

    func testServerSummaryPreviewsAtMostTwoServers() {
        XCTAssertEqual(MCPToolTimelineSupport.serverSummary(for: []), "mcp")
        XCTAssertEqual(MCPToolTimelineSupport.serverSummary(for: ["github"]), "github")
        XCTAssertEqual(MCPToolTimelineSupport.serverSummary(for: ["github", "linear"]), "github, linear")
        XCTAssertEqual(
            MCPToolTimelineSupport.serverSummary(for: [" github ", " \n ", "linear", "github"]),
            "github, mcp +1"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.serverSummary(for: ["github", "linear", "filesystem"]),
            "github, linear +1"
        )
    }

    func testCollapsedTitlePrefersRunningCount() {
        let entries = [
            entry(id: "first", name: "github__search", result: toolResult(callID: "first")),
            entry(id: "second", name: "linear__list", result: nil),
            entry(id: "third", name: "filesystem__read", result: nil)
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(for: entries),
            "MCP github, linear +1: 2 running"
        )
    }

    func testCollapsedTitleUsesSingleToolNameWhenOnlyOneServerContext() {
        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(
                for: [entry(id: "first", name: "github__search", result: toolResult(callID: "first"))]
            ),
            "MCP · search"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(
                for: [entry(id: "first", name: "search", result: toolResult(callID: "first"))]
            ),
            "MCP · search"
        )
    }

    func testCollapsedTitleCanUsePerCallServerTagForSingleEntryInMultiServerContext() {
        let entries = [
            entry(id: "first", name: "github__search", result: toolResult(callID: "first"))
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(for: entries, serverIDs: ["github", "linear"]),
            "github: search"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(for: entries, serverIDs: [" github ", " linear "]),
            "github: search"
        )
    }

    func testCollapsedTitleUsesCallCountWhenComplete() {
        let entries = [
            entry(id: "first", name: "github__search", result: toolResult(callID: "first")),
            entry(id: "second", name: "linear__list", result: toolResult(callID: "second"))
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.collapsedTitle(for: entries),
            "MCP github, linear: 2 calls"
        )
    }

    func testExpandedTitleMatchesServerContext() {
        XCTAssertEqual(
            MCPToolTimelineSupport.expandedTitle(
                for: [entry(id: "first", name: "search")]
            ),
            "Tool"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.expandedTitle(
                for: [
                    entry(id: "first", name: "search"),
                    entry(id: "second", name: "read")
                ]
            ),
            "Tools"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.expandedTitle(
                for: [entry(id: "first", name: "github__search")]
            ),
            "Tools · github"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.expandedTitle(
                for: [
                    entry(id: "first", name: "search"),
                    entry(id: "second", name: "read")
                ],
                serverIDs: [" mcp "]
            ),
            "Tools"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.expandedTitle(
                for: [
                    entry(id: "first", name: "github__search"),
                    entry(id: "second", name: "linear__list")
                ]
            ),
            "Tools"
        )
    }

    func testCompactStatusBadgesAreSuppressedWhileRunning() {
        let entries = [
            entry(id: "first", result: toolResult(callID: "first")),
            entry(id: "second", result: nil)
        ]

        XCTAssertEqual(MCPToolTimelineSupport.compactStatusBadges(for: entries), [])
    }

    func testCompactStatusBadgesUseSuccessThenFailureOrder() {
        let entries = [
            entry(id: "first", result: toolResult(callID: "first")),
            entry(id: "second", result: toolResult(callID: "second")),
            entry(id: "third", result: toolResult(callID: "third", isError: true))
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.compactStatusBadges(for: entries),
            [
                .init(count: 2, icon: "checkmark.circle.fill", tone: .success),
                .init(count: 1, icon: "xmark.circle.fill", tone: .failure)
            ]
        )
    }

    func testStatusSummaryTextOrdersCountsBeforeDuration() {
        let entries = [
            entry(id: "first", result: toolResult(callID: "first", durationSeconds: 0.25)),
            entry(id: "second", result: toolResult(callID: "second", isError: true, durationSeconds: 0.244)),
            entry(id: "third", result: nil)
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.statusSummaryText(for: entries),
            "passed · failed · running · 494ms"
        )
    }

    func testStatusSummaryTextFormatsPluralCountsAndSeconds() {
        let entries = [
            entry(id: "first", result: toolResult(callID: "first", durationSeconds: 0.75)),
            entry(id: "second", result: toolResult(callID: "second", durationSeconds: 0.5)),
            entry(id: "third", result: toolResult(callID: "third", isError: true, durationSeconds: 0.25)),
            entry(id: "fourth", result: toolResult(callID: "fourth", isError: true, durationSeconds: 0.25))
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.statusSummaryText(for: entries),
            "2 passed · 2 failed · 1.8s"
        )
    }

    func testEntryAnimationSignatureIncludesIDsAndStatusTokens() {
        let entries = [
            entry(id: "first", result: nil),
            entry(id: "second", result: toolResult(callID: "second")),
            entry(id: "third", result: toolResult(callID: "third", isError: true))
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.entryAnimationSignature(for: entries),
            "first:running|second:success|third:error"
        )
    }

    func testSummaryRowFlagsRequireMultipleServers() {
        XCTAssertFalse(MCPToolTimelineSupport.shouldShowServerSummaryRow(for: ["github"]))
        XCTAssertFalse(MCPToolTimelineSupport.shouldShowServerSummaryRow(for: [" github ", "github"]))
        XCTAssertTrue(MCPToolTimelineSupport.shouldShowServerSummaryRow(for: ["github", "linear"]))
        XCTAssertFalse(MCPToolTimelineSupport.shouldShowPerCallServerTag(for: ["github"]))
        XCTAssertFalse(MCPToolTimelineSupport.shouldShowPerCallServerTag(for: [" \n ", "mcp"]))
        XCTAssertTrue(MCPToolTimelineSupport.shouldShowPerCallServerTag(for: ["github", "linear"]))
    }

    func testResolvedIconIDUsesConfiguredMappingAndDefaultFallbacks() {
        let mapping = [
            "github": "github-icon",
            "linear": "linear-icon"
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.resolvedIconID(
                forServerID: "github",
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "github-icon"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.resolvedIconID(
                forServerID: "",
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "default-icon"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.resolvedIconID(
                forServerID: " \n ",
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "default-icon"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.resolvedIconID(
                forServerID: " github ",
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "github-icon"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.resolvedIconID(
                forServerID: "unknown",
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "default-icon"
        )
    }

    func testSummaryIconIDUsesFirstServerOrDefault() {
        let mapping = [
            "github": "github-icon",
            "linear": "linear-icon"
        ]

        XCTAssertEqual(
            MCPToolTimelineSupport.summaryIconID(
                for: [" github ", "linear"],
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "github-icon"
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.summaryIconID(
                for: [],
                iconIDByServerID: mapping,
                defaultIconID: "default-icon"
            ),
            "default-icon"
        )
    }

    func testIconStackLayoutCapsDisplayedServersAndComputesWidth() {
        XCTAssertEqual(
            MCPToolTimelineSupport.iconStackLayout(
                for: [" github ", "linear", "filesystem", "slack", "notion", "github"]
            ),
            .init(
                displayedServerIDs: ["github", "linear", "filesystem", "slack"],
                iconFrameSize: 16,
                overlapOffset: 10,
                totalWidth: 46
            )
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.iconStackLayout(
                for: ["github", "linear"],
                maxVisibleCount: 1,
                iconFrameSize: 20,
                overlapOffset: 8
            ),
            .init(
                displayedServerIDs: ["github"],
                iconFrameSize: 20,
                overlapOffset: 8,
                totalWidth: 20
            )
        )
        XCTAssertEqual(
            MCPToolTimelineSupport.iconStackLayout(for: [], maxVisibleCount: 4),
            .init(
                displayedServerIDs: [],
                iconFrameSize: 16,
                overlapOffset: 10,
                totalWidth: 0
            )
        )
    }

    private func entry(
        id: String,
        name: String = "github__search",
        result: ToolResult? = nil
    ) -> MCPToolTimelineSupport.Entry {
        MCPToolTimelineSupport.Entry(
            call: toolCall(id: id, name: name),
            result: result
        )
    }

    private func toolCall(
        id: String,
        name: String
    ) -> ToolCall {
        ToolCall(
            id: id,
            name: name,
            arguments: [:]
        )
    }

    private func toolResult(
        id: String = "result",
        callID: String,
        isError: Bool = false,
        durationSeconds: Double? = nil
    ) -> ToolResult {
        ToolResult(
            id: id,
            toolCallID: callID,
            content: "",
            isError: isError,
            durationSeconds: durationSeconds
        )
    }
}
