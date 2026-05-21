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
}
