import SwiftUI
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

    func testSplitVisibilityMapping() {
        XCTAssertEqual(MainSidebarVisibility.splitVisibility(isVisible: true), .all)
        XCTAssertEqual(MainSidebarVisibility.splitVisibility(isVisible: false), .detailOnly)
    }

    func testIsVisibleTreatsAutomaticAndAllAsVisible() {
        XCTAssertTrue(MainSidebarVisibility.isVisible(.all))
        XCTAssertTrue(MainSidebarVisibility.isVisible(.automatic))
        XCTAssertFalse(MainSidebarVisibility.isVisible(.detailOnly))
    }

    func testToggledVisibilityFlipsBetweenAllAndDetailOnly() {
        XCTAssertEqual(MainSidebarVisibility.toggled(.all), .detailOnly)
        XCTAssertEqual(MainSidebarVisibility.toggled(.detailOnly), .all)
        XCTAssertEqual(MainSidebarVisibility.toggled(.automatic), .detailOnly)
    }

    func testVisibleColumnWidthUsesPersistedBounds() {
        let width = MainSidebarVisibility.columnWidth(
            isVisible: true,
            persistedWidth: Double(SidebarWidthPersistence.defaultWidth)
        )
        XCTAssertEqual(width.min, SidebarWidthPersistence.minimumWidth)
        XCTAssertEqual(width.ideal, SidebarWidthPersistence.defaultWidth)
        XCTAssertEqual(width.max, SidebarWidthPersistence.maximumWidth)
    }

    func testCollapsedToolbarMigrationMatchesOS() {
        if #available(macOS 26, *) {
            XCTAssertTrue(MainSidebarVisibility.sidebarToolbarMigratesWhenCollapsed)
        } else {
            XCTAssertFalse(MainSidebarVisibility.sidebarToolbarMigratesWhenCollapsed)
        }
    }

    func testHiddenColumnWidthDropsToZeroSoMinCannotPinTheSplitOpen() {
        let width = MainSidebarVisibility.columnWidth(
            isVisible: false,
            persistedWidth: Double(SidebarWidthPersistence.defaultWidth)
        )
        XCTAssertEqual(width.min, 0)
        XCTAssertEqual(width.ideal, 0)
        XCTAssertEqual(width.max, 0)
    }
}
