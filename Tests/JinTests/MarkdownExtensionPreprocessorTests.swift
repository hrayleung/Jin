import XCTest
@testable import Jin

final class MarkdownExtensionPreprocessorTests: XCTestCase {
    func testDisplayMathAtDocumentStartDoesNotInsertLeadingBlankLine() {
        let input = "$$x^2$$"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "```math\nx^2\n```")
    }

    func testDisplayMathAfterParagraphKeepsSingleSeparator() {
        let input = "intro\n$$x^2$$"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "intro\n```math\nx^2\n```")
    }

    // MARK: - Delimiter unification (opener/closer with content)

    func testOpenerWithTrailingContentOpensBlock() {
        let input = "$$E = mc^2\n$$\n后文。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "```math\nE = mc^2\n```\n后文。")
    }

    func testCloserWithLeadingContentClosesBlock() {
        let input = "$$\nE = mc^2 $$\n后文。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "```math\nE = mc^2\n```\n后文。")
    }

    func testCloserWithTrailingProseEmitsRemainderAsProse() {
        let input = "$$\nE = mc^2\n$$结论。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "```math\nE = mc^2\n```\n结论。")
    }

    func testOrphanCloserDoesNotSwallowFollowingProse() {
        let input = """
        前文。

        $$E = mc^2
        $$

        这一段不能消失。

        ## 后续标题
        """

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertTrue(output.contains("这一段不能消失。"), "prose after math was swallowed:\n\(output)")
        XCTAssertTrue(output.contains("## 后续标题"), "heading after math was swallowed:\n\(output)")
        XCTAssertTrue(output.contains("```math\nE = mc^2\n```"), "math block missing:\n\(output)")
    }

    func testUnclosedEmptyDelimiterLineSurvivesAtEOF() {
        let input = "结尾段落。\n$$"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "结尾段落。\n$$")
    }

    func testUnclosedOpenerWithContentEmitsPartialMathDuringStreaming() {
        let input = "推导：\n$$\\int_0^1 x \\, dx"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "推导：\n```math\n\\int_0^1 x \\, dx\n```")
    }

    func testBracketBlockStillClosesWithContentCloser() {
        let input = "\\[\nx^2 \\]\n后文。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, "```math\nx^2\n```\n后文。")
    }

    func testEscapedBracketProseIsNotTreatedAsMath() {
        let input = "引用文献 \\[1\\] 与 \\[2\\] 的结论。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, input)
    }

    func testMixedInlineDollarsLineIsLeftAlone() {
        let input = "$$a$$b$$ 混合行保持原样。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, input)
    }

    func testFencedCodeBlockShieldsDollarLines() {
        let input = "```text\n$$not math\n$$\n```\n正文。"

        let output = MarkdownExtensionPreprocessor.preprocess(input)

        XCTAssertEqual(output, input)
    }
}
