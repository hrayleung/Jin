import AppKit
import XCTest
@testable import Jin

/// Folded-list / folded-blockquote contracts. The load-bearing invariant for
/// selection & persisted highlights: every `.prose` group satisfies
/// `attributedString.string == plainText` position-for-position, and every
/// `LinkRange` extracts the expected substring.
@MainActor
final class NativeMarkdownGroupBuilderTests: XCTestCase {
    private func groups(_ markdown: String) -> [NativeMarkdownGroup] {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let key = NativeMarkdownCache.Key(
            markdownText: markdown,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )
        return NativeMarkdownCache.compute(key: key, theme: theme).groups
    }

    private func proseGroups(_ markdown: String) -> [(attributed: NSAttributedString, plain: String, links: [LinkRange])] {
        groups(markdown).compactMap {
            if case let .prose(attributed, plain, links, _) = $0 {
                return (attributed, plain, links)
            }
            return nil
        }
    }

    private func assertOffsetContract(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prose = proseGroups(markdown)
        XCTAssertFalse(prose.isEmpty, "expected at least one prose group", file: file, line: line)
        for group in prose {
            XCTAssertEqual(group.attributed.string, group.plain, "attributedString/plainText diverged", file: file, line: line)
            for link in group.links {
                XCTAssertTrue(
                    NSMaxRange(link.range) <= group.attributed.length,
                    "link range out of bounds",
                    file: file,
                    line: line
                )
            }
        }
    }

    // MARK: - Nested / loose lists fold into ONE prose group

    func testNestedTightListFoldsIntoSingleProseGroup() {
        let markdown = """
        前言段落。

        - 一级项目 A
          - 二级项目 A1
          - 二级项目 A2
            - 三级项目 A2x
        - 一级项目 B

        结尾段落。
        """
        let all = groups(markdown)
        XCTAssertEqual(all.count, 1, "everything is prose-only and must fold into one group; got \(all.count)")
        assertOffsetContract(markdown)

        let prose = proseGroups(markdown)[0]
        XCTAssertTrue(prose.plain.contains("•\t一级项目 A"))
        XCTAssertTrue(prose.plain.contains("◦\t二级项目 A1"))
        XCTAssertTrue(prose.plain.contains("▪\t三级项目 A2x"))
    }

    func testNestedListIndentIncreasesPerLevel() {
        let markdown = """
        - 一级
          - 二级
        """
        let prose = proseGroups(markdown)[0]
        let text = prose.plain as NSString

        func headIndent(atMarker marker: String) -> CGFloat {
            let location = text.range(of: marker).location
            XCTAssertNotEqual(location, NSNotFound, "marker \(marker) missing")
            let style = prose.attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            return style?.headIndent ?? -1
        }

        XCTAssertLessThan(headIndent(atMarker: "•\t"), headIndent(atMarker: "◦\t"))
    }

    func testLooseListWithMultiParagraphItemFolds() {
        let markdown = """
        1. 第一步标题

           第一步的补充说明段落。

        2. 第二步
        """
        let all = groups(markdown)
        XCTAssertEqual(all.count, 1)
        assertOffsetContract(markdown)

        let prose = proseGroups(markdown)[0]
        XCTAssertTrue(prose.plain.contains("1.\t第一步标题"))
        XCTAssertTrue(prose.plain.contains("\n第一步的补充说明段落。"), "continuation paragraph must carry no marker")
        XCTAssertTrue(prose.plain.contains("2.\t第二步"))
    }

    func testWideOrdinalMarkersGetWiderTextColumn() {
        let narrow = proseGroups("1. 项目\n2. 项目")[0]
        let wide = proseGroups("98. 项目\n99. 项目\n100. 项目")[0]

        func textColumn(_ group: (attributed: NSAttributedString, plain: String, links: [LinkRange])) -> CGFloat {
            let style = group.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            return style?.headIndent ?? -1
        }

        XCTAssertGreaterThan(textColumn(wide), textColumn(narrow))
        XCTAssertTrue(wide.plain.contains("100.\t项目"))
    }

    func testLinkInsideFoldedNestedListTranslatesCorrectly() {
        let markdown = """
        - 外层项目
          - 参考 [文档](https://example.com/docs) 链接
        """
        let prose = proseGroups(markdown)[0]
        XCTAssertEqual(prose.links.count, 1)
        let linkText = (prose.attributed.string as NSString).substring(with: prose.links[0].range)
        XCTAssertEqual(linkText, "文档")
        XCTAssertEqual(prose.links[0].url.absoluteString, "https://example.com/docs")
    }

    // MARK: - Widget-bearing lists still take the legacy path

    func testListWithCodeBlockChildFallsBackToComplexList() {
        let markdown = """
        - 普通项目
        - 带代码的项目

          ```swift
          let x = 1
          ```
        """
        let hasComplexList = groups(markdown).contains {
            if case .complexList = $0 { return true }
            return false
        }
        XCTAssertTrue(hasComplexList, "widget-bearing list must keep the per-item view path")
    }

    // MARK: - Folded blockquotes

    func testProseBlockQuoteFoldsWithDepthAttributeAndTint() {
        let markdown = """
        引用之前的段落。

        > 引用的第一段。
        >
        > 引用的第二段。

        引用之后的段落。
        """
        let all = groups(markdown)
        XCTAssertEqual(all.count, 1, "prose-only quote must fold into the prose group")
        assertOffsetContract(markdown)

        let prose = proseGroups(markdown)[0]
        let text = prose.plain as NSString
        let quoteLocation = text.range(of: "引用的第一段").location
        XCTAssertNotEqual(quoteLocation, NSNotFound)

        let depth = prose.attributed.attribute(.jinBlockQuoteDepth, at: quoteLocation, effectiveRange: nil) as? NSNumber
        XCTAssertEqual(depth?.intValue, 1)

        let style = prose.attributed.attribute(.paragraphStyle, at: quoteLocation, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent, 13)

        let beforeLocation = text.range(of: "引用之前").location
        XCTAssertNil(
            prose.attributed.attribute(.jinBlockQuoteDepth, at: beforeLocation, effectiveRange: nil),
            "non-quote prose must not carry the depth attribute"
        )
    }

    func testNestedBlockQuoteGetsDeeperDepth() {
        let markdown = """
        > 外层引用。
        >
        > > 内层引用。
        """
        assertOffsetContract(markdown)
        let prose = proseGroups(markdown)[0]
        let text = prose.plain as NSString

        let outer = prose.attributed.attribute(
            .jinBlockQuoteDepth,
            at: text.range(of: "外层引用").location,
            effectiveRange: nil
        ) as? NSNumber
        let inner = prose.attributed.attribute(
            .jinBlockQuoteDepth,
            at: text.range(of: "内层引用").location,
            effectiveRange: nil
        ) as? NSNumber
        XCTAssertEqual(outer?.intValue, 1)
        XCTAssertEqual(inner?.intValue, 2)
    }

    func testQuoteContainingListFolds() {
        let markdown = """
        > 引用开头。
        >
        > - 引用里的项目一
        > - 引用里的项目二
        """
        let all = groups(markdown)
        XCTAssertEqual(all.count, 1)
        assertOffsetContract(markdown)

        let prose = proseGroups(markdown)[0]
        XCTAssertTrue(prose.plain.contains("•\t引用里的项目一"))
        // List inside the quote must be indented past the quote gutter.
        let text = prose.plain as NSString
        let style = prose.attributed.attribute(
            .paragraphStyle,
            at: text.range(of: "•\t").location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.headIndent ?? -1, 13)
    }

    func testQuoteWithCodeBlockFallsBackToComplexQuote() {
        let markdown = """
        > 引用文字
        >
        > ```swift
        > let x = 1
        > ```
        """
        let hasComplexQuote = groups(markdown).contains {
            if case .complexBlockQuote = $0 { return true }
            return false
        }
        XCTAssertTrue(hasComplexQuote)
    }

    // MARK: - Signature sensitivity

    func testFoldedListSignatureChangesWithNesting() {
        func proseSignature(_ markdown: String) -> UInt64? {
            for group in groups(markdown) {
                if case let .prose(_, _, _, signature) = group { return signature }
            }
            return nil
        }
        XCTAssertNotEqual(
            proseSignature("- A\n- B"),
            proseSignature("- A\n  - B"),
            "nesting structure must change the prose signature"
        )
    }
}
