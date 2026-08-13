import SwiftUI
import XCTest
@testable import Jin

final class MainSidebarSplitSupportTests: XCTestCase {
    func testAnimatableColumnMinimumDoesNotFightCollapse() {
        XCTAssertLessThan(
            MainSidebarSplitSupport.animatableColumnMinimumWidth,
            SidebarWidthPersistence.minimumWidth
        )
        XCTAssertGreaterThan(MainSidebarSplitSupport.animatableColumnMinimumWidth, 0)
    }

    func testVisibilityMapping() {
        XCTAssertTrue(MainSidebarSplitSupport.isVisible(.all))
        XCTAssertTrue(MainSidebarSplitSupport.isVisible(.doubleColumn))
        XCTAssertFalse(MainSidebarSplitSupport.isVisible(.detailOnly))
    }

    func testNextVisibilityTogglesDetailOnly() {
        XCTAssertEqual(MainSidebarSplitSupport.nextVisibility(.all), .detailOnly)
        XCTAssertEqual(MainSidebarSplitSupport.nextVisibility(.detailOnly), .all)
        XCTAssertEqual(MainSidebarSplitSupport.nextVisibility(.doubleColumn), .detailOnly)
    }

    func testSuppressedTransactionDisablesImplicitAnimation() {
        let transaction = MainSidebarSplitSupport.suppressedAnimationTransaction
        XCTAssertNil(transaction.animation)
        XCTAssertTrue(transaction.disablesAnimations)
    }

    func testOpenConversationSnapsInsteadOfInterpolating() {
        XCTAssertTrue(
            MainSidebarSplitSupport.shouldSnapColumnChange(
                reduceMotion: false,
                hasOpenConversation: true
            )
        )
        XCTAssertFalse(
            MainSidebarSplitSupport.shouldSnapColumnChange(
                reduceMotion: false,
                hasOpenConversation: false
            )
        )
        XCTAssertTrue(
            MainSidebarSplitSupport.shouldSnapColumnChange(
                reduceMotion: true,
                hasOpenConversation: false
            )
        )
    }
}
