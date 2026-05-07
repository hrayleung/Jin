import XCTest
@testable import Jin

final class ContentViewSidebarPinnedChromeSupportTests: XCTestCase {
    func testSearchFieldIsActiveWhenFocusedWithBlankSearchText() {
        XCTAssertTrue(
            ContentViewSidebarPinnedChromeSupport.isSearchFieldActive(
                isFocused: true,
                searchText: " \n\t "
            )
        )
    }

    func testSearchFieldIsActiveWhenSearchTextHasContent() {
        XCTAssertTrue(
            ContentViewSidebarPinnedChromeSupport.isSearchFieldActive(
                isFocused: false,
                searchText: " \n roadmap\t "
            )
        )
    }

    func testSearchFieldIsInactiveWhenUnfocusedWithBlankSearchText() {
        XCTAssertFalse(
            ContentViewSidebarPinnedChromeSupport.isSearchFieldActive(
                isFocused: false,
                searchText: " \n\t "
            )
        )
    }
}
