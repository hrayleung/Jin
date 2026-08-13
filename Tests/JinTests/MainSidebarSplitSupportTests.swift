import SwiftUI
import XCTest
@testable import Jin

final class MainSidebarSplitSupportTests: XCTestCase {
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
