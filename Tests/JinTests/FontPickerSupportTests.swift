import XCTest
@testable import Jin

final class FontPickerSupportTests: XCTestCase {
    func testTrimmedSearchTextTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(FontPickerSupport.trimmedSearchText("  Mono \n"), "Mono")
    }

    func testFilteredFamiliesReturnsAllFamiliesForBlankSearch() {
        let families = ["Inter", "SF Mono", "New York"]

        XCTAssertEqual(
            FontPickerSupport.filteredFamilies(families, searchText: " \n "),
            families
        )
    }

    func testFilteredFamiliesMatchesCaseInsensitively() {
        let families = ["Inter", "SF Mono", "New York"]

        XCTAssertEqual(
            FontPickerSupport.filteredFamilies(families, searchText: "mono"),
            ["SF Mono"]
        )
        XCTAssertEqual(
            FontPickerSupport.filteredFamilies(families, searchText: "NEW"),
            ["New York"]
        )
    }

    func testSystemDefaultVisibilityAndEmptySearchTextFollowTrimmedQuery() {
        XCTAssertTrue(FontPickerSupport.shouldShowSystemDefaultRow(searchText: " "))
        XCTAssertFalse(FontPickerSupport.shouldShowSystemDefaultRow(searchText: "mono"))
        XCTAssertNil(FontPickerSupport.emptySearchText(searchText: " ", filteredFamilies: []))
        XCTAssertNil(FontPickerSupport.emptySearchText(searchText: "mono", filteredFamilies: ["SF Mono"]))
        XCTAssertEqual(
            FontPickerSupport.emptySearchText(searchText: " mono ", filteredFamilies: []),
            "mono"
        )
    }

    func testSelectionHelpersNormalizeThroughTypographyRules() {
        XCTAssertTrue(FontPickerSupport.isSystemDefaultSelected(selectedFontFamily: " \n "))
        XCTAssertEqual(FontPickerSupport.selectedFontFamily(" Custom Family "), "Custom Family")
        XCTAssertTrue(
            FontPickerSupport.isFamilySelected(
                "Custom Family",
                selectedFontFamily: " Custom Family "
            )
        )
        XCTAssertFalse(
            FontPickerSupport.isFamilySelected(
                "Other Family",
                selectedFontFamily: " Custom Family "
            )
        )
    }
}
