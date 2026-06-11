import Foundation
import Markdown
import XCTest
@testable import Jin

/// The ZWSP flanking repair must keep fixing genuine CJK emphasis
/// boundaries while never firing on Latin text — an unrestricted version
/// paired Python-style exponent asterisks (`f(x)**2 … g(y)**3`) into a
/// bogus bold span, swallowing the literal `**` glyphs.
final class MarkdownCJKEmphasisBoundaryTests: XCTestCase {
    private func renderedDocument(_ markdown: String) -> Document {
        let prepared = MarkdownRenderPreparation.prepareForRender(markdown, isStreaming: false).text
        return Document(parsing: MarkdownExtensionPreprocessor.preprocess(prepared))
    }

    private func strongTexts(in markdown: String) -> [String] {
        collect(Strong.self, in: renderedDocument(markdown)).map { $0.plainText }
    }

    private func emphasisTexts(in markdown: String) -> [String] {
        collect(Emphasis.self, in: renderedDocument(markdown)).map { $0.plainText }
    }

    private func collect<T: Markup>(_ type: T.Type, in document: Document) -> [T] {
        var result: [T] = []
        func visit(_ markup: any Markup) {
            if let hit = markup as? T { result.append(hit) }
            for child in markup.children { visit(child) }
        }
        visit(document)
        return result
    }

    // MARK: - CJK boundaries must still repair

    func testCJKClosingBoldBoundaryParsesAsStrong() {
        let strongs = strongTexts(in: "**新加坡国际仲裁中心（SIAC）**对该裁决具有管辖权。")
        XCTAssertTrue(
            strongs.contains { $0.contains("新加坡国际仲裁中心") },
            "CJK closing-** flanking repair regressed; strongs: \(strongs)"
        )
    }

    func testCJKOpeningBoldDashBoundaryParsesAsStrong() {
        let strongs = strongTexts(in: "他**——副标题也要加粗**结尾。")
        XCTAssertTrue(
            strongs.contains { $0.contains("副标题也要加粗") },
            "CJK opening-** flanking repair regressed; strongs: \(strongs)"
        )
    }

    func testCJKSingleStarClosingBoundaryParsesAsEmphasis() {
        let emphases = emphasisTexts(in: "这是*斜体（注释）*后续文字。")
        XCTAssertTrue(
            emphases.contains { $0.contains("斜体") },
            "CJK closing-* flanking repair regressed; emphases: \(emphases)"
        )
    }

    // MARK: - Latin text must be left alone

    func testLatinExponentAsterisksStayLiteral() {
        let input = "计算 f(x)**2 与 g(y)**3 的差值，结果记为 h。"

        let repairedLine = MarkdownStructuralRepair.repairLine(input)
        XCTAssertFalse(
            repairedLine.contains("\u{200B}"),
            "ZWSP must not be inserted around Latin exponent asterisks: \(repairedLine.debugDescription)"
        )

        let walk = MarkdownTextLossAudit.textOnlyWalk(renderedDocument(input))
        XCTAssertTrue(
            walk.contains("f(x)**2") && walk.contains("g(y)**3"),
            "literal exponent asterisks were swallowed; rendered text: \(walk.debugDescription)"
        )
        XCTAssertTrue(strongTexts(in: input).isEmpty, "no bold span should appear in exponent prose")
    }

    func testLatinPunctuationBoldStaysUntouchedByRepair() {
        // Native CommonMark already parses this; the repair must not add ZWSP.
        let input = "The **bold (text)** works fine."
        let repairedLine = MarkdownStructuralRepair.repairLine(input)
        XCTAssertEqual(repairedLine, input)
    }

    func testTrailingCJKPunctuationStillRejectsZWSP() {
        // Closing `**：` (punctuation AFTER the marker) is valid CommonMark
        // already — inserting ZWSP there is unnecessary churn.
        let input = "1. **极度集中**：通常将资金集中在少数股票上"
        XCTAssertEqual(MarkdownStructuralRepair.repairLine(input), input)
    }
}
