import XCTest
@testable import Jin

final class CodeExecContentBlockSupportTests: XCTestCase {
    func testCodeLanguageInferenceHandlesSupportedSignals() {
        XCTAssertNil(CodeExecCodeLanguage.infer(from: "   \n"))
        XCTAssertEqual(CodeExecCodeLanguage.infer(from: "#!/bin/bash\necho \"$HOME\""), .shell)
        XCTAssertEqual(CodeExecCodeLanguage.infer(from: "import SwiftUI\nstruct Demo: View {}"), .swift)
        XCTAssertEqual(CodeExecCodeLanguage.infer(from: "const value = 1\nconsole.log(value)"), .javascript)
        XCTAssertEqual(CodeExecCodeLanguage.infer(from: "import matplotlib.pyplot as plt\nprint(1)"), .python)
        XCTAssertEqual(CodeExecCodeLanguage.infer(from: "plain text"), .generic)
    }

    func testCodeLanguageBadgeLabelsMatchDisplayedCopy() {
        XCTAssertEqual(CodeExecCodeLanguage.python.badgeLabel, "Python")
        XCTAssertEqual(CodeExecCodeLanguage.javascript.badgeLabel, "JavaScript")
        XCTAssertEqual(CodeExecCodeLanguage.shell.badgeLabel, "Shell")
        XCTAssertEqual(CodeExecCodeLanguage.swift.badgeLabel, "Swift")
        XCTAssertEqual(CodeExecCodeLanguage.generic.badgeLabel, "Code")
    }

    func testMetricsTreatEmptyTextAsSingleLine() {
        XCTAssertEqual(
            CodeExecContentBlockSupport.metrics(for: ""),
            .init(lineCount: 1, longestLineLength: 0, characterCount: 0)
        )
    }

    func testMetricsPreserveEmptyLinesAndTrackLongestLine() {
        XCTAssertEqual(
            CodeExecContentBlockSupport.metrics(for: "a\n\nlonger"),
            .init(lineCount: 3, longestLineLength: 6, characterCount: 9)
        )
    }

    func testExpandControlUsesLineCountOrCharacterCount() {
        XCTAssertFalse(
            CodeExecContentBlockSupport.showsExpandControl(
                for: metrics(lines: 12, longest: 120, count: 800)
            )
        )
        XCTAssertTrue(
            CodeExecContentBlockSupport.showsExpandControl(
                for: metrics(lines: 13, longest: 1, count: 13)
            )
        )
        XCTAssertTrue(
            CodeExecContentBlockSupport.showsExpandControl(
                for: metrics(lines: 1, longest: 801, count: 801)
            )
        )
    }

    func testVisibleTextTruncatesCollapsedAndExpandedLineLimits() {
        let text = (1...90).map(String.init).joined(separator: "\n")

        let collapsed = CodeExecContentBlockSupport.visibleText(for: text, isExpanded: false)
        XCTAssertEqual(
            CodeExecContentBlockSupport.lines(from: collapsed).count,
            CodeExecContentBlockSupport.collapsedLineLimit
        )
        XCTAssertEqual(collapsed.split(separator: "\n", omittingEmptySubsequences: false).first, "1")
        XCTAssertEqual(collapsed.split(separator: "\n", omittingEmptySubsequences: false).last, "12")

        let expanded = CodeExecContentBlockSupport.visibleText(for: text, isExpanded: true)
        XCTAssertEqual(
            CodeExecContentBlockSupport.lines(from: expanded).count,
            CodeExecContentBlockSupport.expandedRenderLineLimit
        )

        XCTAssertEqual(
            CodeExecContentBlockSupport.visibleText(for: "print(1)", isExpanded: false),
            "print(1)"
        )
    }

    func testVisibleTextCapsMinifiedPayloadsWithoutNewlines() {
        let payload = String(repeating: "a", count: 6_000)

        let collapsed = CodeExecContentBlockSupport.visibleText(for: payload, isExpanded: false)
        XCTAssertEqual(collapsed.count, CodeExecContentBlockSupport.collapsedCharacterLimit)
        XCTAssertTrue(payload.hasPrefix(collapsed))

        let expanded = CodeExecContentBlockSupport.visibleText(for: payload, isExpanded: true)
        XCTAssertEqual(expanded.count, CodeExecContentBlockSupport.expandedCharacterLimit)
        XCTAssertTrue(payload.hasPrefix(expanded))
    }

    func testHiddenLineCountAndExpandCopy() {
        let lineMetrics = CodeExecContentBlockSupport.metrics(
            for: (1...20).map(String.init).joined(separator: "\n")
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.hiddenLineCount(for: lineMetrics, isExpanded: false),
            8
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.hiddenLineCount(for: lineMetrics, isExpanded: true),
            0
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(for: lineMetrics, isExpanded: false),
            "Show 8 more lines"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(
                for: metrics(lines: 13, longest: 1, count: 13),
                isExpanded: false
            ),
            "Show 1 more line"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(for: lineMetrics, isExpanded: true),
            "Show less"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(
                for: metrics(lines: 1, longest: 801, count: 801),
                isExpanded: false
            ),
            "Show more"
        )
        XCTAssertNil(
            CodeExecContentBlockSupport.truncatedRemainderCaption(
                for: metrics(lines: 12, longest: 10, count: 100)
            )
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(
                for: metrics(lines: 81, longest: 1, count: 81)
            ),
            "1 more line — copy for the full output"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(
                for: metrics(lines: 92, longest: 1, count: 92)
            ),
            "12 more lines — copy for the full output"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(
                for: metrics(lines: 1, longest: 5_000, count: 5_000)
            ),
            "More output — copy for the full output"
        )
    }

    func testLineNumberTextMatchesExistingBounds() {
        XCTAssertNil(CodeExecContentBlockSupport.lineNumberText(forLineCount: 1))
        XCTAssertEqual(CodeExecContentBlockSupport.lineNumberText(forLineCount: 3), "1\n2\n3")
        XCTAssertNotNil(CodeExecContentBlockSupport.lineNumberText(forLineCount: 400))
        XCTAssertNil(CodeExecContentBlockSupport.lineNumberText(forLineCount: 401))
    }

    private func metrics(lines: Int, longest: Int, count: Int) -> CodeExecContentBlockSupport.Metrics {
        .init(lineCount: lines, longestLineLength: longest, characterCount: count)
    }
}
