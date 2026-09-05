import AppKit
import Markdown
import XCTest
@testable import Jin

final class MarkdownStrikethroughRenderingTests: XCTestCase {
    private let theme: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")
    private let reportedParagraph = "RL 方差大，你本来就需要 5~10 个 seed 才能下结论。单个 SAC 实验只用 2~4 核，所以："

    func testReportedNumericRangesStayLiteralInFinalAndStreamingOutput() throws {
        for isStreaming in [false, true] {
            let parsed = parse(reportedParagraph, isStreaming: isStreaming)
            let run = try paragraph(in: parsed)

            XCTAssertEqual(run.plainText, reportedParagraph)
            XCTAssertEqual(run.attributedString.string, reportedParagraph)
            XCTAssertEqual(struckText(in: run.attributedString), "")
            XCTAssertTrue(parsed.layout.flatText.contains(reportedParagraph))
        }
    }

    func testEveryStreamingPrefixPreservesNumericRangesWithoutStrikingProse() throws {
        for length in 1...reportedParagraph.count {
            let prefix = String(reportedParagraph.prefix(length))
            let run = try paragraph(in: parse(prefix, isStreaming: true))

            // CommonMark trims trailing whitespace at an unfinished paragraph.
            XCTAssertEqual(run.plainText, prefix.trimmingCharacters(in: .whitespaces))
            XCTAssertEqual(struckText(in: run.attributedString), "", "prefix: \(prefix)")
        }
    }

    func testSingleTildesPreserveTheirDelimitersAndNestedFormatting() throws {
        let cases = [
            ("~text~", "~text~"),
            ("前文🙂 ~**重点** 和 *斜体*~ 后文", "前文🙂 ~重点 和 斜体~ 后文"),
            ("~`5~10`~", "~5~10~"),
            ("~&amp;~", "~&~"),
            ("5~10 个 seed\n每个 2~4 核", "5~10 个 seed 每个 2~4 核"),
            ("在很长的前文之后使用 5~10 个 seed\n2~4 核", "在很长的前文之后使用 5~10 个 seed 2~4 核"),
        ]
        for (source, expected) in cases {
            let run = try paragraph(in: parse(source))
            XCTAssertEqual(run.plainText, expected, source)
            XCTAssertEqual(struckText(in: run.attributedString), "", source)
        }

        let run = try paragraph(in: parse("~**重点**~"))
        let boldFont = try XCTUnwrap(run.attributedString.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
    }

    func testDoubleTildeStrikethroughStillRendersWithNumericRanges() throws {
        let cases = [
            ("~~gone~~ `code` here", "gone code here", "gone"),
            ("~~旧配置~~：5~10 个 seed，2~4 核", "旧配置：5~10 个 seed，2~4 核", "旧配置"),
            ("~~5~10 个 seed，2~4 核~~", "5~10 个 seed，2~4 核", "5~10 个 seed，2~4 核"),
            ("~~**旧配置**~~", "旧配置", "旧配置"),
        ]
        for (source, expected, expectedStrike) in cases {
            let run = try paragraph(in: parse(source))
            XCTAssertEqual(run.plainText, expected, source)
            XCTAssertEqual(struckText(in: run.attributedString), expectedStrike, source)
        }
    }

    func testMultilineDelimiterFallbackHandlesLineEndingsAndEscapes() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let cases = [
                ("较长的中文前文🙂 5~10\(newline)2~4", "较长的中文前文🙂 5~10 2~4", ""),
                ("较长的中文前文🙂 ~~旧配置\(newline)已弃用~~", "较长的中文前文🙂 旧配置 已弃用", "旧配置 已弃用"),
                ("较长的中文前文🙂 \\~~内容\(newline)结束~", "较长的中文前文🙂 ~~内容 结束~", ""),
                ("较长的中文前文🙂 \\~~~内容\(newline)结束~~", "较长的中文前文🙂 ~内容 结束", "内容 结束"),
            ]
            for (source, expected, expectedStrike) in cases {
                let run = try paragraph(in: parse(source))
                XCTAssertEqual(run.plainText, expected, source)
                XCTAssertEqual(struckText(in: run.attributedString), expectedStrike, source)
            }
        }
    }

    func testLinkLabelsKeepLiteralTildesAndCorrectClickableRange() throws {
        let destination = "https://example.com/~user/5~10"
        let run = try paragraph(in: parse("[5~10 个 seed，2~4 核](\(destination))"))

        XCTAssertEqual(run.plainText, "5~10 个 seed，2~4 核")
        XCTAssertEqual(struckText(in: run.attributedString), "")
        XCTAssertEqual(run.linkURLs.count, 1)
        let link = try XCTUnwrap(run.linkURLs.first)
        XCTAssertEqual(link.url.absoluteString, destination)
        XCTAssertEqual(link.range, NSRange(location: 0, length: run.attributedString.length))
    }

    func testCodeAutolinksAndEscapedTildesAreUnchanged() throws {
        let cases = [
            ("`5~10 个 seed，2~4 核`", "5~10 个 seed，2~4 核"),
            (#"5\~10 个 seed，2\~4 核"#, "5~10 个 seed，2~4 核"),
            ("<https://example.com/~user/5~10>", "https://example.com/~user/5~10"),
        ]
        for (source, expected) in cases {
            let run = try paragraph(in: parse(source))
            XCTAssertEqual(run.plainText, expected, source)
            XCTAssertEqual(struckText(in: run.attributedString), "", source)
        }

        let parsed = parse("~~~text\n5~10 个 seed，2~4 核\n~~~")
        guard case let .codeBlock(_, source, _) = parsed.blocks.first else {
            return XCTFail("expected fenced code block")
        }
        XCTAssertEqual(source, "5~10 个 seed，2~4 核\n")
    }

    func testTableCellsKeepRangesAfterEscapedPipesAndInlineCode() {
        let parsed = parse("""
        | 配置 | 备注 |
        | --- | --- |
        | a\\|b `x\\|y` 5~10 个 seed，2~4 核 | ~~旧配置~~ |
        """)
        guard case let .table(_, _, rows) = parsed.blocks.first else {
            return XCTFail("expected table block")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][0].plainText, "a|b x|y 5~10 个 seed，2~4 核")
        XCTAssertEqual(struckText(in: rows[0][0].attributedString), "")
        XCTAssertEqual(struckText(in: rows[0][1].attributedString), "旧配置")
    }

    func testProgrammaticallyConstructedStrikethroughKeepsItsStyle() {
        let strike = Strikethrough([Markdown.Text("gone")])
        let run = MarkdownInlineRenderer(theme: theme).render(inlineChildren: [strike])

        XCTAssertEqual(run.plainText, "gone")
        XCTAssertEqual(struckText(in: run.attributedString), "gone")
    }

    private func parse(_ source: String, isStreaming: Bool = false) -> NativeMarkdownCache.Value {
        NativeMarkdownCache.compute(
            key: .init(
                markdownText: source,
                isStreaming: isStreaming,
                renderPlainText: false,
                appFontFamily: "",
                codeFontFamily: ""
            ),
            theme: theme
        )
    }

    private func paragraph(in parsed: NativeMarkdownCache.Value) throws -> InlineRun {
        XCTAssertEqual(parsed.blocks.count, 1)
        let block = try XCTUnwrap(parsed.blocks.first)
        guard case let .paragraph(run) = block else {
            XCTFail("expected paragraph, got \(block)")
            throw NSError(domain: "MarkdownStrikethroughRenderingTests", code: 1)
        }
        return run
    }

    private func struckText(in attributed: NSAttributedString) -> String {
        var text = ""
        attributed.enumerateAttribute(
            .strikethroughStyle,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            if let style = value as? Int, style != 0 {
                text.append((attributed.string as NSString).substring(with: range))
            }
        }
        return text
    }
}
