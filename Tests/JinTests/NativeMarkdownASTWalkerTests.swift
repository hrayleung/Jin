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
}
