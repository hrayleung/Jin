import XCTest
@testable import Jin

final class ConversationRenameSupportTests: XCTestCase {
    func testNormalizedTitleTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(ConversationRenameSupport.normalizedTitle(" \n Project Notes\t "), "Project Notes")
    }

    func testNormalizedTitleRejectsBlankTitle() {
        XCTAssertNil(ConversationRenameSupport.normalizedTitle(" \n\t "))
    }

    func testCanSaveTitleFollowsNormalizedTitleAvailability() {
        XCTAssertTrue(ConversationRenameSupport.canSaveTitle(" New Title "))
        XCTAssertFalse(ConversationRenameSupport.canSaveTitle(" \n\t "))
    }
}
