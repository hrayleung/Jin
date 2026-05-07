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

    func testExpandControlMatchesExistingLineLengthAndCharacterThresholds() {
        XCTAssertFalse(CodeExecContentBlockSupport.showsExpandControl(for: metrics(lines: 12, longest: 120, count: 800)))
        XCTAssertTrue(CodeExecContentBlockSupport.showsExpandControl(for: metrics(lines: 13, longest: 1, count: 13)))
        XCTAssertTrue(CodeExecContentBlockSupport.showsExpandControl(for: metrics(lines: 1, longest: 121, count: 121)))
        XCTAssertTrue(CodeExecContentBlockSupport.showsExpandControl(for: metrics(lines: 1, longest: 1, count: 801)))
    }

    func testCurrentMaxHeightOnlyAppliesWhenExpandable() {
        XCTAssertNil(
            CodeExecContentBlockSupport.currentMaxHeight(
                for: metrics(lines: 1, longest: 1, count: 1),
                isExpanded: false,
                collapsedHeight: 176,
                expandedHeight: 320
            )
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.currentMaxHeight(
                for: metrics(lines: 13, longest: 1, count: 13),
                isExpanded: false,
                collapsedHeight: 176,
                expandedHeight: 320
            ),
            176
        )
        XCTAssertEqual(
            CodeExecContentBlockSupport.currentMaxHeight(
                for: metrics(lines: 13, longest: 1, count: 13),
                isExpanded: true,
                collapsedHeight: 176,
                expandedHeight: 320
            ),
            320
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
