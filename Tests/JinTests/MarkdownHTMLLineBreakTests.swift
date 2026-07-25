import AppKit
import Markdown
import XCTest
@testable import Jin

/// `<br>` is the only way to break a line inside a GFM table cell, so models
/// emit it constantly. Before the fix it rendered as the literal text `<br>`
/// in an inline-code chip.
final class MarkdownHTMLLineBreakTests: XCTestCase {
    private let theme: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")

    // MARK: - Tag recognition

    func testRecognisesBreakTagSpellings() {
        for tag in ["<br>", "<br/>", "<br />", "<BR>", "<Br/>", "<br\t/>", "</br>", "<br  >"] {
            XCTAssertTrue(MarkdownHTMLLineBreak.isBreakTag(tag), "expected \(tag) to be a break tag")
        }
    }

    func testRejectsNonBreakTags() {
        for tag in ["<b>", "<br class=\"x\">", "<break>", "<brx>", "<b r>", "<>", "br", "<bra/>", ""] {
            XCTAssertFalse(MarkdownHTMLLineBreak.isBreakTag(tag), "expected \(tag) not to be a break tag")
        }
    }

    func testBreakOnlyBlockDetection() {
        XCTAssertTrue(MarkdownHTMLLineBreak.isBreakOnlyBlock("<br>\n"))
        XCTAssertTrue(MarkdownHTMLLineBreak.isBreakOnlyBlock("<br/>\n<br />\n"))
        // Type-7 HTML blocks run to the next blank line, so a block that also
        // carries text must stay intact — dropping it would delete the text.
        XCTAssertFalse(MarkdownHTMLLineBreak.isBreakOnlyBlock("<br>\n后续正文\n"))
        XCTAssertFalse(MarkdownHTMLLineBreak.isBreakOnlyBlock("<div>\n内容\n</div>\n"))
        XCTAssertFalse(MarkdownHTMLLineBreak.isBreakOnlyBlock("\n"))
    }

    // MARK: - Rendering

    func testInlineBreakRendersAsNewlineInParagraph() {
        let run = paragraphRun(parsing: "段落一<br>段落二<br/>段落三<br />段落四")

        XCTAssertEqual(run.plainText, "段落一\n段落二\n段落三\n段落四")
        XCTAssertEqual(run.attributedString.string, run.plainText)
    }

    func testInlineBreakInsideTableCellRendersAsNewline() {
        let markdown = """
        | 评价维度 | 组合 |
        | :--- | :--- |
        | 系统 / 架构顶级会议<br>(EuroSys/NSDI) | **12 篇**<br>*(EuroSys × 5)* |
        """
        let document = Document(parsing: markdown)
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .table(_, _, rows) = blocks[0] else {
            return XCTFail("expected table block, got \(blocks[0])")
        }
        XCTAssertEqual(rows[0][0].plainText, "系统 / 架构顶级会议\n(EuroSys/NSDI)")
        XCTAssertEqual(rows[0][1].plainText, "12 篇\n(EuroSys × 5)")
    }

    func testBreakInsideEmphasisKeepsSurroundingStyling() {
        // The break must not close the bold frame: both halves stay bold.
        let run = paragraphRun(parsing: "**上半<br>下半**")

        XCTAssertEqual(run.plainText, "上半\n下半")
        let fonts = fontRuns(in: run.attributedString)
        XCTAssertEqual(fonts.count, 1, "bold styling should span the break, got \(fonts.count) font runs")
        XCTAssertTrue(
            fonts[0].fontDescriptor.symbolicTraits.contains(.bold),
            "text around a <br> inside ** ** must stay bold"
        )
    }

    func testNonBreakInlineHTMLStaysLiteral() {
        // Raw HTML execution stays off by policy — only `<br>` is special.
        let run = paragraphRun(parsing: "正文里有 <b>内联标签</b>。")

        XCTAssertEqual(run.plainText, "正文里有 <b>内联标签</b>。")
    }

    func testStandaloneBreakBlockIsDropped() {
        let document = Document(parsing: "上文段落。\n\n<br>\n\n下文段落。")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 2, "the <br>-only block should not render, got \(blocks)")
        for block in blocks {
            if case .htmlBlock = block { XCTFail("expected no html block, got \(blocks)") }
        }
    }

    func testHTMLBlockCarryingTextIsStillRendered() {
        let document = Document(parsing: "<div class=\"note\">\n块内容。\n</div>")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        guard case let .htmlBlock(text) = blocks.first else {
            return XCTFail("expected an html block, got \(blocks)")
        }
        XCTAssertTrue(text.contains("块内容。"))
    }

    func testBreakLaysOutAsASecondLineAtAWidthThatWouldNotWrap() {
        // The property the user actually sees: two lines, not one long line
        // with a literal `<br>` in the middle.
        let broken = paragraphRun(parsing: "顶级荣誉<br>(全球最高奖)")
        let unbroken = paragraphRun(parsing: "顶级荣誉 (全球最高奖)")

        XCTAssertEqual(lineFragmentCount(for: unbroken.attributedString, width: 600), 1)
        XCTAssertEqual(lineFragmentCount(for: broken.attributedString, width: 600), 2)
    }

    // MARK: - Helpers

    private func paragraphRun(parsing markdown: String) -> InlineRun {
        let document = Document(parsing: markdown)
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)
        guard case let .paragraph(run) = blocks.first else {
            XCTFail("expected a paragraph block, got \(blocks)")
            return .empty
        }
        return run
    }

    private func lineFragmentCount(for attributed: NSAttributedString, width: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: attributed)
        let layout = JinMarkdownLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        var count = 0
        var glyphIndex = 0
        while glyphIndex < layout.numberOfGlyphs {
            var glyphRange = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            count += 1
            glyphIndex = glyphRange.upperBound
        }
        return count
    }

    private func fontRuns(in attributed: NSAttributedString) -> [NSFont] {
        var fonts: [NSFont] = []
        attributed.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, _, _ in
            if let font = value as? NSFont { fonts.append(font) }
        }
        return fonts
    }
}
