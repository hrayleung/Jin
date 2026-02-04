import Markdown
import XCTest
@_spi(MarkdownMath) import MarkdownView

final class InlineMathParsingTests: XCTestCase {
    func testMarkdownViewMathParserExtractsInlineEquations() throws {
        let source = #"其中 $\mathcal{S}_V$ 是所谓的 Satake 层 Hecke 特征层 (Hecke Eigensheaf) $\mathcal{M}\sigma$, 满足："#

        let parser = MathParser(text: source)
        let extracted = parser.mathRepresentations
            .filter { $0.kind == .inlineEquation || $0.kind == .inlineParenthesesEquation }
            .map(\.range)
            .map { String(source[$0]) }

        XCTAssertEqual(extracted, [#"$\mathcal{S}_V$"#, #"$\mathcal{M}\sigma$"#])
    }

    func testSwiftMarkdownKeepsInlineMathDelimitersInTextNodes() throws {
        let source = #"其中 $\mathcal{S}_V$ 是所谓的 Satake 层 Hecke 特征层 (Hecke Eigensheaf) $\mathcal{M}\sigma$, 满足："#

        let document = Document(parsing: source, options: [.parseBlockDirectives])

        var collector = TextNodeCollector()
        collector.visit(document)

        let joined = collector.texts.joined(separator: "|")
        XCTAssertTrue(
            joined.contains(#"$\mathcal{S}_V$"#) && joined.contains(#"$\mathcal{M}\sigma$"#),
            "Expected inline math to appear in Text nodes. Got: \(collector.texts)"
        )
    }
}

private struct TextNodeCollector: MarkupWalker {
    var texts: [String] = []

    mutating func defaultVisit(_ markup: any Markup) {
        descendInto(markup)
    }

    mutating func visitText(_ text: Markdown.Text) {
        texts.append(text.plainText)
    }
}
