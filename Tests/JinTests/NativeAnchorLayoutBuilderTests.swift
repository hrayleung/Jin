import XCTest
@testable import Jin

/// Anchor-layout block IDs must be deterministic: a fresh UUID per build
/// defeated `SelectionAggregator.update`'s equality gate on every streaming
/// flush (full highlight re-walk per flush) and grew its registration
/// dictionary without bound.
@MainActor
final class NativeAnchorLayoutBuilderTests: XCTestCase {
    private func parsedGroups(_ markdown: String) -> [NativeMarkdownGroup] {
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

    func testRepeatedBuildsProduceIdenticalAggregatorBlocks() {
        let markdown = """
        段落一。

        > 引用段落
        >
        > - 嵌套列表项 A
        > - 嵌套列表项 B

        1. 第一项

           续段。

        段落二。
        """
        let groups = parsedGroups(markdown)

        let first = NativeAnchorLayoutBuilder.build(groups: groups)
        let second = NativeAnchorLayoutBuilder.build(groups: groups)

        XCTAssertFalse(first.aggregatorBlocks.isEmpty)
        XCTAssertEqual(first.aggregatorBlocks, second.aggregatorBlocks)
        XCTAssertEqual(first.flatText, second.flatText)
    }

    func testDistinctPathsProduceDistinctIDs() {
        XCTAssertNotEqual(
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [0]),
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [1])
        )
        XCTAssertNotEqual(
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [0, 1]),
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [0, 2])
        )
        XCTAssertNotEqual(
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [1, 2]),
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [12])
        )
    }

    func testSamePathIsStableAcrossCalls() {
        XCTAssertEqual(
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [3, 1, 4]),
            NativeAnchorLayoutBuilder.deterministicBlockID(path: [3, 1, 4])
        )
    }
}
