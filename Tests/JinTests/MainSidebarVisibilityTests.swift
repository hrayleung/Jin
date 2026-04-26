import XCTest
@testable import Jin

final class MainSidebarVisibilityTests: XCTestCase {
    func testDefaultStateIsVisible() {
        XCTAssertTrue(MainSidebarVisibility.defaultIsVisible)
    }

    func testToggleSwitchesBetweenVisibleAndHiddenStates() {
        XCTAssertFalse(MainSidebarVisibility.toggled(true))
        XCTAssertTrue(MainSidebarVisibility.toggled(false))
    }
}
