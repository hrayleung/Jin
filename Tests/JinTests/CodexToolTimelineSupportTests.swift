import XCTest
@testable import Jin

final class CodexToolTimelineSupportTests: XCTestCase {
    func testDisplayModeFallsBackToExpanded() {
        XCTAssertEqual(CodexToolTimelineSupport.displayMode(rawValue: "collapseOnComplete"), .collapseOnComplete)
        XCTAssertEqual(CodexToolTimelineSupport.displayMode(rawValue: "alwaysCollapsed"), .alwaysCollapsed)
        XCTAssertEqual(CodexToolTimelineSupport.displayMode(rawValue: nil), .expanded)
        XCTAssertEqual(CodexToolTimelineSupport.displayMode(rawValue: "unknown"), .expanded)
    }

    func testInitialExpansionFollowsDisplayModeAndStreamingState() {
        XCTAssertTrue(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .expanded
            )
        )
        XCTAssertTrue(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertTrue(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .expanded
            )
        )
        XCTAssertFalse(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            CodexToolTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .alwaysCollapsed
            )
        )
    }

    func testStreamingChangeExpansionMatchesExistingModeRules() {
        XCTAssertEqual(
            CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .expanded
            ),
            true
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .collapseOnComplete
            ),
            true
        )
        XCTAssertNil(
            CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .collapseOnComplete
            ),
            false
        )
        XCTAssertNil(
            CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .expanded
            )
        )
    }

    func testEntriesWrapActivitiesAndPreserveIDs() {
        let activities = [
            activity(id: "first", toolName: "shell", status: .running),
            activity(id: "second", toolName: "file_read", status: .completed)
        ]

        let entries = CodexToolTimelineSupport.entries(for: activities)

        XCTAssertEqual(entries.map(\.id), ["first", "second"])
        XCTAssertEqual(entries.map(\.activity.toolName), ["shell", "file_read"])
    }

    func testExecutionStatusMapsActivityStatuses() {
        XCTAssertEqual(
            CodexToolTimelineSupport.executionStatus(for: activity(id: "running", status: .running)),
            .running
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.executionStatus(for: activity(id: "queued", status: .unknown("queued"))),
            .running
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.executionStatus(for: activity(id: "done", status: .completed)),
            .success
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.executionStatus(for: activity(id: "failed", status: .failed)),
            .error
        )
    }

    func testCountsClassifyEntriesByExecutionStatus() {
        let entries = CodexToolTimelineSupport.entries(
            for: [
                activity(id: "running", status: .running),
                activity(id: "queued", status: .unknown("queued")),
                activity(id: "done", status: .completed),
                activity(id: "failed", status: .failed)
            ]
        )

        XCTAssertEqual(
            CodexToolTimelineSupport.counts(for: entries),
            .init(running: 2, succeeded: 1, failed: 1)
        )
    }

    func testCollapsedTitleUsesSingleToolNameAndTruncatesLongNames() {
        XCTAssertEqual(
            CodexToolTimelineSupport.collapsedTitle(
                for: entries([
                    activity(id: "one", toolName: "shell", status: .running)
                ])
            ),
            "Codex: shell"
        )

        let longName = String(repeating: "a", count: 70)
        XCTAssertEqual(
            CodexToolTimelineSupport.collapsedTitle(
                for: entries([
                    activity(id: "one", toolName: longName, status: .completed)
                ])
            ),
            "Codex: \(String(repeating: "a", count: 57))..."
        )
    }

    func testCollapsedTitlePrefersRunningCountForMultipleEntries() {
        XCTAssertEqual(
            CodexToolTimelineSupport.collapsedTitle(
                for: entries([
                    activity(id: "one", status: .running),
                    activity(id: "two", status: .unknown("queued")),
                    activity(id: "three", status: .completed)
                ])
            ),
            "Codex: 2 running"
        )
    }

    func testCollapsedTitleUsesToolCountWhenMultipleEntriesComplete() {
        XCTAssertEqual(
            CodexToolTimelineSupport.collapsedTitle(
                for: entries([
                    activity(id: "one", status: .completed),
                    activity(id: "two", status: .failed)
                ])
            ),
            "Codex: 2 tools"
        )
    }

    func testCompactStatusIsNilWhileAnyEntryIsRunning() {
        XCTAssertNil(
            CodexToolTimelineSupport.compactStatus(
                for: entries([
                    activity(id: "one", status: .completed),
                    activity(id: "two", status: .running)
                ])
            )
        )
    }

    func testCompactStatusReportsFailures() {
        XCTAssertEqual(
            CodexToolTimelineSupport.compactStatus(
                for: entries([
                    activity(id: "one", status: .failed)
                ])
            ),
            .init(text: "failed", icon: "xmark.circle.fill", tone: .failure)
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.compactStatus(
                for: entries([
                    activity(id: "one", status: .completed),
                    activity(id: "two", status: .failed),
                    activity(id: "three", status: .failed)
                ])
            ),
            .init(text: "ok / 2 failed", icon: "xmark.circle.fill", tone: .failure)
        )
    }

    func testCompactStatusReportsSuccesses() {
        XCTAssertEqual(
            CodexToolTimelineSupport.compactStatus(
                for: entries([
                    activity(id: "one", status: .completed)
                ])
            ),
            .init(text: "Succeeded", icon: "checkmark.circle.fill", tone: .success)
        )
        XCTAssertEqual(
            CodexToolTimelineSupport.compactStatus(
                for: entries([
                    activity(id: "one", status: .completed),
                    activity(id: "two", status: .completed)
                ])
            ),
            .init(text: "All succeeded", icon: "checkmark.circle.fill", tone: .success)
        )
    }

    func testStatusSummaryTextFormatsCountsInExistingOrder() {
        XCTAssertEqual(
            CodexToolTimelineSupport.statusSummaryText(
                for: entries([
                    activity(id: "one", status: .completed),
                    activity(id: "two", status: .completed),
                    activity(id: "three", status: .failed),
                    activity(id: "four", status: .running)
                ])
            ),
            "(2 successes / failed / running)"
        )
        XCTAssertNil(CodexToolTimelineSupport.statusSummaryText(for: []))
    }

    func testEntryAnimationSignatureUsesIDsAndExecutionStatusDescriptions() {
        XCTAssertEqual(
            CodexToolTimelineSupport.entryAnimationSignature(
                for: entries([
                    activity(id: "one", status: .running),
                    activity(id: "two", status: .completed),
                    activity(id: "three", status: .failed)
                ])
            ),
            "one:running|two:success|three:error"
        )
    }

    func testArgumentSummaryUsesPreferredKeysAndCondensesWhitespace() {
        XCTAssertEqual(
            CodexToolTimelineSupport.argumentSummary(
                for: [
                    "ignored": AnyCodable("skip"),
                    "path": AnyCodable("  Sources/UI/CodexToolTimelineView.swift\n")
                ]
            ),
            "Sources/UI/CodexToolTimelineView.swift"
        )
    }

    func testArgumentSummarySkipsBlankPreferredValues() {
        XCTAssertEqual(
            CodexToolTimelineSupport.argumentSummary(
                for: [
                    "command": AnyCodable(" \n "),
                    "path": AnyCodable("  Sources/UI/CodexToolTimelineView.swift\n")
                ]
            ),
            "Sources/UI/CodexToolTimelineView.swift"
        )
    }

    func testArgumentSummaryFallsBackToJSONWhenPreferredValuesAreBlank() {
        XCTAssertEqual(
            CodexToolTimelineSupport.argumentSummary(
                for: [
                    "command": AnyCodable(" \n "),
                    "limit": AnyCodable(5)
                ]
            ),
            "{\"command\":\" \\n \",\"limit\":5}"
        )
    }

    func testArgumentSummaryFallsBackToCompactSortedJSON() {
        XCTAssertEqual(
            CodexToolTimelineSupport.argumentSummary(
                for: [
                    "zeta": AnyCodable(2),
                    "alpha": AnyCodable("one")
                ]
            ),
            "{\"alpha\":\"one\",\"zeta\":2}"
        )
    }

    func testArgumentSummaryReturnsNilForEmptyOrInvalidJSONObject() {
        XCTAssertNil(CodexToolTimelineSupport.argumentSummary(for: [:]))
        XCTAssertNil(CodexToolTimelineSupport.argumentSummary(for: ["bad": AnyCodable(Double.nan)]))
    }

    func testArgumentSummaryTruncatesLongValues() {
        XCTAssertEqual(
            CodexToolTimelineSupport.argumentSummary(
                for: ["command": AnyCodable(String(repeating: "a", count: 10))],
                maxLength: 8
            ),
            "aaaaa..."
        )
    }

    func testFormattedArgumentsJSONPrettyPrintsSortedKeys() {
        XCTAssertEqual(
            CodexToolTimelineSupport.formattedArgumentsJSON(
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
    }

    func testFormattedArgumentsJSONReturnsNilForEmptyOrInvalidJSONObject() {
        XCTAssertNil(CodexToolTimelineSupport.formattedArgumentsJSON(for: [:]))
        XCTAssertNil(CodexToolTimelineSupport.formattedArgumentsJSON(for: ["bad": AnyCodable(Double.nan)]))
    }

    func testStatusLabelsMatchTimelineCopy() {
        XCTAssertEqual(CodexToolTimelineSupport.statusLabel(for: .running), "Running")
        XCTAssertEqual(CodexToolTimelineSupport.statusLabel(for: .success), "Done")
        XCTAssertEqual(CodexToolTimelineSupport.statusLabel(for: .error), "Failed")
    }

    func testToolIconNameMapsCommandFamilies() {
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "shell"), "terminal")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "python script"), "terminal")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "file_write"), "pencil.line")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "file_read"), "doc.text")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "ripgrep search"), "magnifyingglass")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "rg"), "magnifyingglass")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "list files"), "folder")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "mcp/github"), "puzzlepiece")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "spawn agent"), "person.2")
        XCTAssertEqual(CodexToolTimelineSupport.toolIconName(for: "unknown"), "gearshape")
    }

    func testOneLineCondensesWhitespaceAndTruncates() {
        XCTAssertEqual(CodexToolTimelineSupport.oneLine("  one\n two\tthree  ", maxLength: 20), "one two three")
        XCTAssertEqual(CodexToolTimelineSupport.oneLine("abcdef", maxLength: 5), "ab...")
    }

    private func entries(_ activities: [CodexToolActivity]) -> [CodexToolTimelineSupport.Entry] {
        CodexToolTimelineSupport.entries(for: activities)
    }

    private func activity(
        id: String,
        toolName: String = "shell",
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
