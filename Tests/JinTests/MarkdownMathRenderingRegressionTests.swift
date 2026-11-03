import AppKit
import Markdown
import SwiftMath
import XCTest
@testable import Jin

@MainActor
final class MarkdownMathRenderingRegressionTests: XCTestCase {
    private let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")

    private func render(_ source: String, streaming: Bool = false) -> [NativeMarkdownBlock] {
        NativeMarkdownCache.compute(key: .init(
            markdownText: source, isStreaming: streaming, renderPlainText: false,
            appFontFamily: "", codeFontFamily: ""
        ), theme: theme).blocks
    }

    private func assertMath(_ run: InlineRun, sources: [String], file: StaticString = #filePath, line: UInt = #line) {
        var actual: [String] = []
        run.attributedString.enumerateAttribute(.jinInlineMathSource, in: NSRange(location: 0, length: run.attributedString.length)) { value, range, _ in
            guard let source = value as? String else { return }
            actual.append(source)
            XCTAssertNotNil(run.attributedString.attribute(.attachment, at: range.location, effectiveRange: nil), source, file: file, line: line)
        }
        XCTAssertEqual(actual, sources, file: file, line: line)
        XCTAssertEqual(run.plainText, run.attributedString.string, file: file, line: line)
    }

    func testReportedInlineFormulasRenderAndCopyOriginalSource() throws {
        let formulas = [#"\(S_X\)"#, #"\(S_O\)"#, #"\(\gamma_X、\gamma_O\)"#, #"\(L_{\mathrm{TTFT}}\)"#, #"\(\tau\)"#, #"\(N=1024,\alpha=0.25\)"#]
        for formula in formulas {
            let source = "说明：\(formula) 对应的大小。"
            for streaming in [false, true] {
                guard case .paragraph(let run) = try XCTUnwrap(render(source, streaming: streaming).first) else {
                    return XCTFail("Expected a paragraph")
                }
                assertMath(run, sources: [formula])
                XCTAssertEqual(JinMessageTextView.latexExpandedPlainString(from: run.attributedString), source)
            }
        }
    }

    func testReportedTableKeepsThreeColumnsAndAllCells() throws {
        let source = #"""
        | 情况 | 判断 | 动作 |
        |---|---|---|
        | \(\Delta>\tau\) | C2C 相对更忙 | 减小 α，多用 Asym |
        | \(\Delta<-\tau\) | HBM 相对更忙 | 增大 α，多用 Sym |
        | \(|\Delta|\leq\tau\) | 两者差距不大 | 保持 α |
        """#
        guard case .table(let header, _, let rows) = try XCTUnwrap(render(source).first) else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(header.count, 3)
        XCTAssertEqual(rows.count, 3)
        for (row, formula) in zip(rows, [#"\(\Delta>\tau\)"#, #"\(\Delta<-\tau\)"#, #"\(|\Delta|\leq\tau\)"#]) {
            XCTAssertEqual(row.count, 3)
            assertMath(row[0], sources: [formula])
        }
        XCTAssertEqual(rows.last?[1].plainText, "两者差距不大")
        XCTAssertEqual(rows.last?[2].plainText, "保持 α")
    }

    func testMathPunctuationSurvivesMarkdownAndEmphasis() throws {
        let formulas = [#"\(a*b*c\)"#, #"$x_1+y_2$"#, #"\(\operatorname*{argmax}_{x}f(x)\)"#, #"$|x|<\tau$"#]
        for formula in formulas {
            guard case .paragraph(let run) = try XCTUnwrap(render("**公式 \(formula)** 后文").first) else {
                return XCTFail("Expected a paragraph")
            }
            assertMath(run, sources: [formula])
            XCTAssertEqual(JinMessageTextView.latexExpandedPlainString(from: run.attributedString), "公式 \(formula) 后文")
        }
    }

    func testReportedDisplayFormulasRenderThroughLabelAndImage() throws {
        let formulas = [
            #"O_{m,n}\mathrel{+}=partial"#,
            #"N_{\mathrm{sym}}=\lfloor\alpha N\rfloor"#,
            #"W=[W_{\mathrm{sym}}\mid W_{\mathrm{asym}}]"#,
            #"\sum_{m\in\mathcal A}\frac{S_m}{TPOT_m}\leq BW_{\mathrm{avail}}^{\mathrm{C2C}}"#,
            #"BW^{\mathrm{HBM}}=\frac{\gamma_XS_X+\gamma_OS_O}{L_{\mathrm{TTFT}}}"#,
            #"\alpha_{t+1}=\operatorname{clip}_{[0,1]}\left(\alpha_t-\eta_t\operatorname{sign}(\Delta)\right)"#
        ]
        for formula in formulas {
            guard case .mathBlock(let latex) = try XCTUnwrap(render("\\[\n\(formula)\n\\]").first),
                  case .rendered(let list) = MathRenderer.prepare(latex) else {
                XCTFail("Expected rendered display math: \(formula)")
                continue
            }
            let label = MTMathUILabel()
            label.mathList = list
            XCTAssertGreaterThan(label.intrinsicContentSize.height, 0)
            let (error, image) = MTMathImage(latex: latex, fontSize: 20, textColor: .black).asImage()
            XCTAssertNil(error)
            XCTAssertNotNil(try XCTUnwrap(image).tiffRepresentation)
        }
    }

    func testCodeAndHTMLKeepTheirLiteralMathSyntax() throws {
        for source in [
            #"`\(x_i\)` and `$y$`"#,
            "`line one\n\\(x_i\\)`",
            "```text\n\\(x_i\\) $y$\n```",
            "~~~text\n\\(x_i\\) $y$\n~~~",
            "    \\(x_i\\) $y$",
            "<div>\n\\(x_i\\) $y$\n</div>",
            #"a <span title="$x$">b</span>"#
        ] {
            let prepared = MarkdownInlineMathPreprocessor.prepare(source)
            XCTAssertEqual(prepared.text, source)
        }
        guard case .paragraph(let run) = try XCTUnwrap(render(#"`\(x_i\)` and \(y_i\)"#).first) else {
            return XCTFail("Expected a paragraph")
        }
        assertMath(run, sources: [#"\(y_i\)"#])
        XCTAssertEqual(JinMessageTextView.latexExpandedPlainString(from: run.attributedString), #"\(x_i\) and \(y_i\)"#)
    }

    func testLinksKeepDestinationsAndRenderMathInInlineLabels() throws {
        for source in [
            #"[link](https://example.com/$x$ "title $y$") and \(z\)"#,
            "[link][ref] and \\(z\\)\n\n[ref]: https://example.com/$x$ \"title $y$\""
        ] {
            guard case .paragraph(let run) = try XCTUnwrap(render(source).first) else {
                return XCTFail("Expected a paragraph")
            }
            assertMath(run, sources: [#"\(z\)"#])
            XCTAssertEqual(run.linkURLs.first?.url.absoluteString, "https://example.com/$x$")
        }
        guard case .paragraph(let run) = try XCTUnwrap(render(#"[\(x_i\)](https://example.com)"#).first) else {
            return XCTFail("Expected a paragraph")
        }
        assertMath(run, sources: [#"\(x_i\)"#])
        XCTAssertEqual(run.linkURLs.first?.url.absoluteString, "https://example.com")
    }

    func testEscapedDelimitersAndCurrencyStayLiteral() throws {
        for (source, expected) in [
            (#"\$x\$ and \\(y\\)"#, #"$x$ and \(y\)"#),
            (#"$AAPL、$TSLA；预算 $100–$200。"#, #"$AAPL、$TSLA；预算 $100–$200。"#)
        ] {
            guard case .paragraph(let run) = try XCTUnwrap(render(source).first) else {
                return XCTFail("Expected a paragraph")
            }
            assertMath(run, sources: [])
            XCTAssertEqual(run.plainText, expected)
        }
    }

    func testUnsupportedMathPreservesExactFallbackSource() throws {
        let formula = #"\(\unknowncommand{x_1}|y|\)"#
        guard case .paragraph(let run) = try XCTUnwrap(render("before \(formula) after").first) else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(run.plainText, "before \(formula) after")
        XCTAssertEqual(JinMessageTextView.latexExpandedPlainString(from: run.attributedString), run.plainText)
    }

    func testTableExportsPreserveFormulaSourceAndRoundTrip() throws {
        let formula = #"\(|\Delta|\leq\tau\)"#
        let source = "| 情况 | 动作 |\n|---|---|\n| \(formula) | 保持 α |"
        guard case .table(let header, let alignments, let rows) = try XCTUnwrap(render(source).first) else {
            return XCTFail("Expected a table")
        }
        let table = MarkdownTableView(header: header, alignments: alignments, rows: rows)
        let markdown = table.markdownPlainText(columnCount: 2)
        XCTAssertTrue(markdown.contains(formula))
        XCTAssertEqual(table.tsvPlainText(columnCount: 2), "情况\t动作\n\(formula)\t保持 α")
        guard case .table(_, _, let restored) = try XCTUnwrap(render(markdown).first) else {
            return XCTFail("Expected exported markdown to remain a table")
        }
        assertMath(restored[0][0], sources: [formula])
        XCTAssertEqual(restored[0][1].plainText, "保持 α")
    }

    func testSymbolCommaAndRelationKeepTheirMathMeaning() throws {
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: #"\gamma_X、\gamma_O"#))
        XCTAssertTrue(list.atoms.contains { $0.type == .punctuation && $0.nucleus == "、" })
        let relation = try XCTUnwrap(MTMathListBuilder.build(fromString: #"\mathrel{+}"#)?.atoms.first)
        XCTAssertEqual(relation.type, .relation)
        XCTAssertEqual(relation.nucleus, "+")
        // Unsupported compound relation arguments must not lose their content.
        for formula in [#"\mathrel"#, #"\mathrel{}"#, #"\mathrel{\frac{a}{b}}"#] {
            guard case .raw(let source) = MathRenderer.prepare(formula) else {
                XCTFail("Expected raw fallback for \(formula)")
                continue
            }
            XCTAssertEqual(source, formula)
        }
    }

    func testListItemsAndTableCodeUseTheSameProtection() throws {
        let formulas = [#"\(S_X\)"#, #"\(\gamma_X、\gamma_O\)"#, #"\(L_{\mathrm{TTFT}}\)"#]
        let source = formulas.map { "- \($0)：说明。" }.joined(separator: "\n")
        guard case .bulletList(let items, _) = try XCTUnwrap(render(source).first) else {
            return XCTFail("Expected a list")
        }
        for (item, formula) in zip(items, formulas) {
            guard case .paragraph(let run) = try XCTUnwrap(item.children.first) else {
                return XCTFail("Expected a list paragraph")
            }
            assertMath(run, sources: [formula])
        }
        let tableSource = #"""
        | prose | code | formula |
        |---|---|---|
        | a \| b \| c \| d \| e \| f | `$x$` | \(y\) |
        """#
        guard case .table(_, _, let rows) = try XCTUnwrap(render(tableSource).first) else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(rows[0][1].plainText, "$x$")
        assertMath(rows[0][1], sources: [])
        assertMath(rows[0][2], sources: [#"\(y\)"#])
    }
}
