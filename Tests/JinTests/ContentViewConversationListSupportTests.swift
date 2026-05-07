import XCTest
@testable import Jin

final class ContentViewConversationListSupportTests: XCTestCase {
    func testNormalizedSearchQueryTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            ContentViewConversationListSupport.normalizedSearchQuery(" \n release notes\t "),
            "release notes"
        )
    }

    func testNormalizedSearchQueryReturnsEmptyStringForBlankSearchText() {
        XCTAssertEqual(
            ContentViewConversationListSupport.normalizedSearchQuery(" \n\t "),
            ""
        )
    }
}
