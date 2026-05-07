import XCTest
@testable import Jin

final class AgentToolTimelineSupportTests: XCTestCase {
    func testDisplayModeFallsBackToExpanded() {
        XCTAssertEqual(AgentToolTimelineSupport.displayMode(rawValue: "collapseOnComplete"), .collapseOnComplete)
        XCTAssertEqual(AgentToolTimelineSupport.displayMode(rawValue: "alwaysCollapsed"), .alwaysCollapsed)
        XCTAssertEqual(AgentToolTimelineSupport.displayMode(rawValue: nil), .expanded)
        XCTAssertEqual(AgentToolTimelineSupport.displayMode(rawValue: "unknown"), .expanded)
    }

    func testInitialExpansionFollowsDisplayModeAndStreamingState() {
        XCTAssertTrue(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .expanded
            )
        )
        XCTAssertTrue(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertTrue(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .expanded
            )
        )
        XCTAssertFalse(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            AgentToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .alwaysCollapsed
            )
        )
    }

    func testStreamingChangeExpansionMatchesExistingModeRules() {
        XCTAssertEqual(
            AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .expanded
            ),
            true
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .collapseOnComplete
            ),
            true
        )
        XCTAssertNil(
            AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .collapseOnComplete
            ),
            false
        )
        XCTAssertNil(
            AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .expanded
            )
        )
    }

    func testCollapsedTitleUsesSingleToolName() {
        let activities = [
            activity(id: "1", toolName: "agent__shell", status: .running)
        ]

        XCTAssertEqual(AgentToolTimelineSupport.collapsedTitle(for: activities), "Agent · shell")
    }

    func testCollapsedTitlePrefersRunningCountForMultipleActivities() {
        let activities = [
            activity(id: "1", toolName: "agent__shell", status: .running),
            activity(id: "2", toolName: "agent__file_read", status: .unknown("queued")),
            activity(id: "3", toolName: "agent__grep", status: .completed)
        ]

        XCTAssertEqual(AgentToolTimelineSupport.collapsedTitle(for: activities), "Agent · 2 running")
    }

    func testCollapsedTitleUsesToolCountWhenComplete() {
        let activities = [
            activity(id: "1", status: .completed),
            activity(id: "2", status: .failed),
            activity(id: "3", status: .completed)
        ]

        XCTAssertEqual(AgentToolTimelineSupport.collapsedTitle(for: activities), "Agent · 3 tools")
    }

    func testCompactStatusIsNilWhileAnyActivityIsRunning() {
        let activities = [
            activity(id: "1", status: .completed),
            activity(id: "2", status: .running)
        ]

        XCTAssertNil(AgentToolTimelineSupport.compactStatus(for: activities))
    }

    func testCompactStatusReportsFailures() {
        XCTAssertEqual(
            AgentToolTimelineSupport.compactStatus(for: [activity(id: "1", status: .failed)]),
            .init(text: "Failed", icon: "xmark.circle.fill", tone: .failure)
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.compactStatus(
                for: [
                    activity(id: "1", status: .completed),
                    activity(id: "2", status: .failed),
                    activity(id: "3", status: .failed)
                ]
            ),
            .init(text: "1 ok / 2 failed", icon: "xmark.circle.fill", tone: .failure)
        )
    }

    func testCompactStatusReportsSuccesses() {
        XCTAssertEqual(
            AgentToolTimelineSupport.compactStatus(for: [activity(id: "1", status: .completed)]),
            .init(text: "Succeeded", icon: "checkmark.circle.fill", tone: .success)
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.compactStatus(
                for: [
                    activity(id: "1", status: .completed),
                    activity(id: "2", status: .completed)
                ]
            ),
            .init(text: "All succeeded", icon: "checkmark.circle.fill", tone: .success)
        )
    }

    func testExecutionStatusMapsActivityStatuses() {
        XCTAssertEqual(
            AgentToolTimelineSupport.executionStatus(for: activity(id: "1", status: .running)),
            .running
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.executionStatus(for: activity(id: "2", status: .unknown("queued"))),
            .running
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.executionStatus(for: activity(id: "3", status: .completed)),
            .success
        )
        XCTAssertEqual(
            AgentToolTimelineSupport.executionStatus(for: activity(id: "4", status: .failed)),
            .error
        )
    }

    func testDisplayNameStripsAgentPrefix() {
        XCTAssertEqual(AgentToolTimelineSupport.displayName(for: "agent__file_read"), "file_read")
        XCTAssertEqual(AgentToolTimelineSupport.displayName(for: "shell"), "shell")
    }

    func testToolIconNameMapsKnownToolFamilies() {
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "agent__shell"), "terminal")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "execute_command"), "terminal")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "file_read"), "doc.text")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "file_write"), "square.and.pencil")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "file_edit"), "pencil.line")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "glob"), "doc.text.magnifyingglass")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "grep"), "magnifyingglass")
        XCTAssertEqual(AgentToolTimelineSupport.toolIconName(for: "unknown_tool"), "gearshape")
    }

    func testArgumentSummaryUsesPreferredKeysAndCondensesWhitespace() {
        let summary = AgentToolTimelineSupport.argumentSummary(
            for: [
                "ignored": AnyCodable("not shown"),
                "path": AnyCodable("  Sources/UI/AgentToolTimelineView.swift\n")
            ]
        )

        XCTAssertEqual(summary, "Sources/UI/AgentToolTimelineView.swift")
    }

    func testArgumentSummarySkipsBlankPreferredValues() {
        let summary = AgentToolTimelineSupport.argumentSummary(
            for: [
                "command": AnyCodable(" \n "),
                "path": AnyCodable("  Sources/UI/AgentToolTimelineView.swift\n")
            ]
        )

        XCTAssertEqual(summary, "Sources/UI/AgentToolTimelineView.swift")
    }

    func testArgumentSummaryReturnsNilForEmptyOrUnsupportedArguments() {
        XCTAssertNil(AgentToolTimelineSupport.argumentSummary(for: [:]))
        XCTAssertNil(AgentToolTimelineSupport.argumentSummary(for: ["limit": AnyCodable(25)]))
        XCTAssertNil(AgentToolTimelineSupport.argumentSummary(for: ["command": AnyCodable(" \n ")]))
    }

    func testArgumentSummaryTruncatesLongValues() {
        let summary = AgentToolTimelineSupport.argumentSummary(
            for: ["command": AnyCodable(String(repeating: "a", count: 10))],
            maxLength: 8
        )

        XCTAssertEqual(summary, "aaaaa...")
    }

    func testFormattedArgumentsJSONPrettyPrintsSortedKeys() {
        let json = AgentToolTimelineSupport.formattedArgumentsJSON(
            for: [
                "zeta": AnyCodable(2),
                "alpha": AnyCodable("one")
            ]
        )

        XCTAssertEqual(
            json,
            """
            {
              "alpha" : "one",
              "zeta" : 2
            }
            """
        )
    }

    func testStatusLabelsMatchTimelineCopy() {
        XCTAssertEqual(AgentToolTimelineSupport.statusLabel(for: .running), "Running")
        XCTAssertEqual(AgentToolTimelineSupport.statusLabel(for: .success), "Done")
        XCTAssertEqual(AgentToolTimelineSupport.statusLabel(for: .error), "Failed")
    }

    func testEntryAnimationSignatureIncludesIdsAndStatuses() {
        let activities = [
            activity(id: "first", status: .running),
            activity(id: "second", status: .failed)
        ]

        XCTAssertEqual(
            AgentToolTimelineSupport.entryAnimationSignature(for: activities),
            "first:running|second:failed"
        )
    }

    private func activity(
        id: String,
        toolName: String = "agent__shell",
        status: CodexToolActivityStatus,
        arguments: [String: AnyCodable] = [:]
    ) -> CodexToolActivity {
        CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments
        )
    }
}
