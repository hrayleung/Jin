import XCTest
@testable import Jin

final class AssistantIconPickerSupportTests: XCTestCase {
    func testEmojiDisplayItemsPreserveSectionHeadersAndChunkRows() {
        let sections = [
            AssistantEmojiCatalog.Section(title: "People", emojis: ["😀", "😄", "😎"]),
            AssistantEmojiCatalog.Section(title: "Objects", emojis: ["💡"])
        ]

        let items = AssistantEmojiDisplayItemFactory.makeDisplayItems(
            from: sections,
            columnCount: 2
        )

        XCTAssertEqual(
            items,
            [
                .header("People"),
                .row(AssistantEmojiRow(id: "People-0-😀", emojis: ["😀", "😄"])),
                .row(AssistantEmojiRow(id: "People-1-😎", emojis: ["😎"])),
                .header("Objects"),
                .row(AssistantEmojiRow(id: "Objects-0-💡", emojis: ["💡"]))
            ]
        )
    }

    func testChunkedRejectsInvalidSize() {
        XCTAssertTrue(AssistantIconPickerLayoutSupport.chunked(["a"], into: 0).isEmpty)
    }

    func testFilteredSymbolCategoriesReturnsAllCategoriesForBlankTrimmedSearch() {
        let categories = [
            AssistantIconCategory(name: "Technology", icons: ["brain", "cpu"]),
            AssistantIconCategory(name: "Creative", icons: ["paintbrush.fill"])
        ]

        let filtered = AssistantIconPickerLayoutSupport.filteredSymbolCategories(
            categories,
            searchText: " \n "
        )

        XCTAssertEqual(filtered.map(\.name), ["Technology", "Creative"])
        XCTAssertEqual(filtered.map(\.icons), [["brain", "cpu"], ["paintbrush.fill"]])
    }

    func testFilteredSymbolCategoriesKeepsWholeCategoryWhenNameMatches() {
        let categories = [
            AssistantIconCategory(name: "Technology", icons: ["brain", "cpu"]),
            AssistantIconCategory(name: "Creative", icons: ["paintbrush.fill"])
        ]

        let filtered = AssistantIconPickerLayoutSupport.filteredSymbolCategories(
            categories,
            searchText: "tech"
        )

        XCTAssertEqual(filtered.map(\.name), ["Technology"])
        XCTAssertEqual(filtered.first?.icons, ["brain", "cpu"])
    }

    func testFilteredSymbolCategoriesFiltersIconsWhenOnlyIconsMatch() {
        let categories = [
            AssistantIconCategory(name: "Technology", icons: ["brain", "cpu", "bolt.fill"]),
            AssistantIconCategory(name: "Creative", icons: ["paintbrush.fill", "camera.fill"])
        ]

        let filtered = AssistantIconPickerLayoutSupport.filteredSymbolCategories(
            categories,
            searchText: "fill"
        )

        XCTAssertEqual(filtered.map(\.name), ["Technology", "Creative"])
        XCTAssertEqual(filtered.map(\.icons), [["bolt.fill"], ["paintbrush.fill", "camera.fill"]])
    }

    func testFilteredSymbolCategoriesDropsCategoriesWithoutMatches() {
        let categories = [
            AssistantIconCategory(name: "Technology", icons: ["brain", "cpu"]),
            AssistantIconCategory(name: "Creative", icons: ["paintbrush.fill"])
        ]

        let filtered = AssistantIconPickerLayoutSupport.filteredSymbolCategories(
            categories,
            searchText: "calendar"
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testEmojiDisplayItemFactoryRejectsInvalidColumnCount() {
        let sections = [
            AssistantEmojiCatalog.Section(title: "People", emojis: ["😀"])
        ]

        XCTAssertTrue(
            AssistantEmojiDisplayItemFactory.makeDisplayItems(from: sections, columnCount: 0).isEmpty
        )
    }
}
