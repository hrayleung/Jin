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

    func testExpandControlUsesLineCountOnlyBecauseLongLinesWrap() {
        XCTAssertFalse(
            CodeExecContentBlockSupport.showsExpandControl(
                for: metrics(lines: 12, longest: 400, count: 800)
            )
        )
        XCTAssertTrue(
            CodeExecContentBlockSupport.showsExpandControl(
                for: metrics(lines: 13, longest: 1, count: 13)
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

    func testHiddenLineCountAndExpandCopy() {
        let metrics = CodeExecContentBlockSupport.metrics(
            for: (1...20).map(String.init).joined(separator: "\n")
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.hiddenLineCount(for: metrics, isExpanded: false),
            8
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.hiddenLineCount(for: metrics, isExpanded: true),
            0
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(hiddenLineCount: 8, isExpanded: false),
            "Show 8 more lines"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(hiddenLineCount: 1, isExpanded: false),
            "Show 1 more line"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.expandControlTitle(hiddenLineCount: 8, isExpanded: true),
            "Show less"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(hiddenLineCount: 0),
            nil
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(hiddenLineCount: 1),
            "1 more line — copy for the full output"
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.truncatedRemainderCaption(hiddenLineCount: 12),
            "12 more lines — copy for the full output"
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
