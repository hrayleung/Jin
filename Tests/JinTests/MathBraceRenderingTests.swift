import AppKit
import Markdown
import XCTest
@testable import Jin
@testable import SwiftMath

final class MathBraceRenderingTests: XCTestCase {
    private let examples = [
        #"\underbrace{X_{M\times K}}_{\text{输入}}\times\underbrace{W_{K\times N}}_{\text{固定的模型权重}}=\underbrace{O_{M\times N}}_{\text{输出}}"#,
        #"\underbrace{X_{1024\times4096}}_{\text{1024 个 token}}\times W_{4096\times16384}=O_{1024\times16384}"#,
        #"\underbrace{X_{1\times4096}}_{\text{当前这个新 token}}\times W_{4096\times16384}=O_{1\times16384}"#
    ]

    func testReportedFormulasRenderThroughMarkdown() throws {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        for latex in examples {
            let source = "说明：\n\n\\[\n\(latex)\n\\]\n\n后文。"
            let prepared = MarkdownExtensionPreprocessor.preprocess(source)
            let blocks = MarkdownASTWalker(theme: theme).walk(document: Document(parsing: prepared))
            let formulas = blocks.compactMap { block -> String? in
                if case .mathBlock(let source) = block { return source }
                return nil
            }
            XCTAssertEqual(formulas.count, 1)
            let formula = try XCTUnwrap(formulas.first)
            guard case .rendered = MathRenderer.prepare(formula) else {
                XCTFail("Formula fell back to raw LaTeX: \(formula)")
                continue
            }
            let renderer = MTMathImage(latex: formula, fontSize: 24, textColor: .black)
            let (error, image) = renderer.asImage()
            XCTAssertNil(error)
            let rendered = try XCTUnwrap(image)
            XCTAssertGreaterThan(rendered.size.width, 0)
            XCTAssertGreaterThan(rendered.size.height, 24)
            XCTAssertNotNil(rendered.tiffRepresentation)
        }
    }

    func testBraceLimitsAreCenteredAndRetainChineseText() throws {
        for isOver in [false, true] {
            let command = isOver ? "overbrace" : "underbrace"
            let script = isOver ? "^" : "_"
            let latex = "\\\(command){X_{M\\times K}}\(script){\\text{固定的模型权重}}"
            let list = try XCTUnwrap(MTMathListBuilder.build(fromString: latex))
            let atom = try XCTUnwrap(list.atoms.first as? MTMathBrace)
            let annotation = try XCTUnwrap(isOver ? atom.superScript : atom.subScript)
            XCTAssertEqual(annotation.atoms.map(\.nucleus).joined(), "固定的模型权重")
            let copy = try XCTUnwrap(list.finalized.atoms.first as? MTMathBrace)
            XCTAssertEqual(copy.isOver, isOver)
            XCTAssertFalse(copy.innerList === atom.innerList)

            for style in [MTLineStyle.display, .text, .script] {
                let font = try XCTUnwrap(MTFontManager.fontManager.defaultFont)
                let tokenizer = MTAtomTokenizer(font: font, style: style)
                let elements = tokenizer.tokenize(list.finalized.atoms)
                // No duplicate side scripts and no breaks inside a brace.
                XCTAssertEqual(elements.count, 1)
                XCTAssertTrue(try XCTUnwrap(elements.first).indivisible)
                let typesetter = MTTypesetter(withFont: font, style: style, cramped: false, spaced: false)
                let display = try XCTUnwrap(typesetter.makeBrace(atom) as? MTLargeOpLimitsDisplay)
                let base = try XCTUnwrap(display.nucleus as? MTBraceDisplay)
                let limit = try XCTUnwrap(isOver ? display.upperLimit : display.lowerLimit)
                display.position = CGPoint(x: 31, y: 47)
                XCTAssertEqual(display.width, max(base.width, limit.width), accuracy: 0.01)
                XCTAssertEqual(base.position.x + base.width / 2, limit.position.x + limit.width / 2, accuracy: 0.01)
                XCTAssertEqual(base.width, base.inner.width, accuracy: 0.01)
                XCTAssertEqual(base.inner.position.y, display.position.y, accuracy: 0.01)
                if isOver {
                    XCTAssertGreaterThan(limit.position.y - limit.descent, base.position.y + base.ascent)
                    XCTAssertGreaterThan(base.ascent, base.inner.ascent)
                } else {
                    XCTAssertLessThan(limit.position.y + limit.ascent, base.position.y - base.descent)
                    XCTAssertGreaterThan(base.descent, base.inner.descent)
                }
            }
            // Rendering must not consume the source atom's annotation.
            XCTAssertTrue((isOver ? atom.superScript : atom.subScript) === annotation)
        }
    }

    func testBraceSerializationAndNestedConstructs() throws {
        let sources = [
            #"\overbrace{a+b}^{n}"#,
            #"\underbrace{x}_i^j"#,
            #"\overbrace{\underbrace{a+b}_{n}+c}^{m}"#,
            #"\frac{\underbrace{x+y}_{n}}{\overbrace{z}^{m}}"#,
            #"\underbrace{}_{0}"#,
            #"\overbrace{x}"#,
            #"\underbrace{\frac{a}{b}}_{\text{输入}}"#
        ]
        for source in sources {
            let list = try XCTUnwrap(MTMathListBuilder.build(fromString: source))
            let serialized = MTMathListBuilder.mathListToString(list)
            XCTAssertTrue(serialized.contains("brace{"))
            XCTAssertNotNil(MTMathListBuilder.build(fromString: serialized))
            for size: CGFloat in [12, 24] {
                let renderer = MTMathImage(latex: source, fontSize: size, textColor: .white, labelMode: .text)
                let (error, image) = renderer.asImage()
                XCTAssertNil(error)
                XCTAssertNotNil(try XCTUnwrap(image).tiffRepresentation)
            }
        }
    }

    func testReportedFormulaWrapsWithoutLosingAnnotations() throws {
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: examples[0]))
        let font = try XCTUnwrap(MTFontManager.fontManager.defaultFont)
        let wide = try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: .display))
        let narrow = try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: .display, maxWidth: 200))
        XCTAssertGreaterThan(narrow.ascent + narrow.descent, wide.ascent + wide.descent)
        XCTAssertLessThanOrEqual(narrow.width, 200)
        func braceCount(_ display: MTDisplay) -> Int {
            if let limits = display as? MTLargeOpLimitsDisplay, limits.nucleus is MTBraceDisplay {
                XCTAssertNotNil(limits.lowerLimit)
                return 1
            }
            return (display as? MTMathListDisplay)?.subDisplays.reduce(0) { $0 + braceCount($1) } ?? 0
        }
        XCTAssertEqual(braceCount(narrow), 3)
    }

    func testIncompleteAndUnsupportedMathKeepsOriginalSource() {
        for source in [#"\underbrace"#, #"\overbrace{"#, #"\underbrace{X}_{\text{输入}"#, #"\unknowncommand{x}"#] {
            guard case .raw(let original) = MathRenderer.prepare(source) else {
                XCTFail("Expected raw source for \(source)")
                continue
            }
            XCTAssertEqual(original, source)
        }
    }
}
