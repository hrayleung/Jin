import Markdown
import XCTest
@_spi(MarkdownMath) import MarkdownView
@testable import Jin

final class DisplayMathBlockNormalizationTests: XCTestCase {
    func testNormalizingMathDelimitersForMarkdownViewMakesInlineDisplayMathParseAsBlockDirective() throws {
        let uuid = "69FC9126-76CF-4757-89AB-2139606FD955"
        let raw = "最终简化为 2x2 矩阵： $$x$$"

        let replacedBefore = raw.replacingFirstDisplayMathWithDirective(uuid: uuid)
        XCTAssertEqual(blockDirectives(in: replacedBefore).count, 0)

        let normalized = raw.normalizingMathDelimitersForMarkdownView()
        let replacedAfter = normalized.replacingFirstDisplayMathWithDirective(uuid: uuid)
        let directives = blockDirectives(in: replacedAfter)

        XCTAssertEqual(directives.count, 1)
        XCTAssertEqual(directives.first?.name, "math")
        let args = directives.first?.argumentText.parseNameValueArguments() ?? []
        XCTAssertEqual(args.first(where: { $0.name == "uuid" })?.value, uuid)
    }

    func testNormalizingMathDelimitersForMarkdownViewInsertsBlankLineAfterDisplayMathWhenTextFollows() {
        let raw = "$$x$$\n下一行"
        XCTAssertEqual(raw.normalizingMathDelimitersForMarkdownView(), "$$x$$\n\n下一行")
    }
}

private func blockDirectives(in markdown: String) -> [BlockDirective] {
    let document = Document(parsing: markdown, options: [.parseBlockDirectives])
    var collector = BlockDirectiveCollector()
    collector.visit(document)
    return collector.directives
}

private struct BlockDirectiveCollector: MarkupWalker {
    var directives: [BlockDirective] = []

    mutating func defaultVisit(_ markup: any Markup) {
        descendInto(markup)
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) {
        directives.append(blockDirective)
    }
}

private extension String {
    func replacingFirstDisplayMathWithDirective(uuid: String) -> String {
        var text = self
        let parser = MathParser(text: text)
        guard let math = parser.mathRepresentations.first(where: { !$0.kind.isInlineMath }) else {
            return text
        }
        text.replaceSubrange(math.range, with: "@math(uuid:\(uuid))")
        return text
    }
}

private extension MathParser.MathRepresentation.Kind {
    var isInlineMath: Bool {
        switch self {
        case .inlineEquation, .inlineParenthesesEquation:
            return true
        default:
            return false
        }
    }
}
