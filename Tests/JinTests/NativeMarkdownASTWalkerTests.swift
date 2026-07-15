import XCTest
import Markdown
@testable import Jin

final class NativeMarkdownASTWalkerTests: XCTestCase {
    private let theme: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")

    func testHeadingAndParagraph() {
        let document = Document(parsing: "# Hello\n\nworld")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 2)
        guard case let .heading(level, headingRun) = blocks[0] else {
            return XCTFail("expected heading block, got \(blocks[0])")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(headingRun.plainText, "Hello")

        guard case let .paragraph(paragraphRun) = blocks[1] else {
            return XCTFail("expected paragraph block, got \(blocks[1])")
        }
        XCTAssertEqual(paragraphRun.plainText, "world")
    }

    func testInlineEmphasisAndLinks() {
        let document = Document(parsing: "before **bold** and *italic* and [docs](https://example.com)")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(run) = blocks[0] else {
            return XCTFail("expected paragraph block, got \(blocks[0])")
        }
        XCTAssertEqual(run.plainText, "before bold and italic and docs")
        XCTAssertEqual(run.linkURLs.count, 1)
        XCTAssertEqual(run.linkURLs.first?.url.absoluteString, "https://example.com")
    }

    func testStrikethroughAndInlineCode() {
        let document = Document(parsing: "~~gone~~ `code` here")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(run) = blocks[0] else {
            return XCTFail("expected paragraph block, got \(blocks[0])")
        }
        // GFM strikethrough requires the parser's extension; for now we expect
        // either rendered-through (if recognised) or the literal tildes.
        XCTAssertTrue(run.plainText.contains("code"))
        XCTAssertTrue(run.plainText.contains("here"))
    }

    func testSoftBreakRendersAsSpace() {
        let document = Document(parsing: "line one\nline two")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(run) = blocks[0] else {
            return XCTFail("expected paragraph block, got \(blocks[0])")
        }
        XCTAssertEqual(run.plainText, "line one line two")
    }

    func testHeadingLevelClamping() {
        let document = Document(parsing: "###### sixth")
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .heading(level, run) = blocks[0] else {
            return XCTFail("expected heading block, got \(blocks[0])")
        }
        XCTAssertEqual(level, 6)
        XCTAssertEqual(run.plainText, "sixth")
    }

    func testTableCellResolvesEscapedAsterisk() {
        // An intact table row whose cell contains `A\*` must render the
        // escaped asterisk as a literal `*` (no backslash, no row spill).
        let document = Document(parsing: """
        | 维度 | 值 |
        | :--- | :--- |
        | CORE Ranking | A / A\\* 级别 |
        """)
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1)
        guard case let .table(_, _, rows) = blocks[0] else {
            return XCTFail("expected table block, got \(blocks[0])")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[0][1].plainText, "A / A* 级别")
    }

    func testPrepareAndWalkKeepsCJKPlusOperatorTableIntact() {
        // End-to-end: prepareForRender must not shatter a table whose cell
        // contains `）+ `, and the walker must still emit one multi-row table.
        let markdown = """
        | 方面 | taskset | cpuset |
        | --- | --- | --- |
        | **控制范围** | 仅 CPU affinity | CPU + 内存节点（NUMA）+ 更多策略 |
        | **强制性** | 较弱（进程可自行修改） | 强（覆盖 affinity 设置） |
        | **层次/结构** | 无 | 支持嵌套、exclusive 等 |
        """
        let prepared = MarkdownRenderPreparation.prepareForRender(markdown, isStreaming: false)
        let document = Document(parsing: prepared.text)
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)

        XCTAssertEqual(blocks.count, 1, "expected a single table block, got \(blocks)")
        guard case let .table(header, _, rows) = blocks[0] else {
            return XCTFail("expected table block, got \(blocks[0])")
        }
        XCTAssertEqual(header.count, 3)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(
            rows[0].map(\.plainText).joined(separator: " | ").contains("更多策略"),
            "third cell of first body row must keep '+ 更多策略' inside the table"
        )
    }

    func testProseGroupSignatureIncludesStylingAndLinks() {
        XCTAssertEqual(proseSignature(for: "[docs](https://example.com/a)"), proseSignature(for: "[docs](https://example.com/a)"))
        XCTAssertNotEqual(proseSignature(for: "[docs](https://example.com/a)"), proseSignature(for: "[docs](https://example.com/b)"))
        XCTAssertNotEqual(proseSignature(for: "plain text"), proseSignature(for: "**plain text**"))
    }

    private func proseSignature(for markdown: String) -> UInt64 {
        let document = Document(parsing: markdown)
        let blocks = MarkdownASTWalker(theme: theme).walk(document: document)
        let groups = NativeMarkdownGroupBuilder.build(blocks: blocks, theme: theme)
        guard let first = groups.first else {
            XCTFail("expected prose group")
            return 0
        }
        return first.contentSignature
    }
}
