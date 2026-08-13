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

    func testLastUsedConversationSkipsExcludedAndEmptyRows() {
        struct Row {
            let id: UUID
            let hasMessages: Bool
        }

        let empty = Row(id: UUID(), hasMessages: false)
        let excluded = Row(id: UUID(), hasMessages: true)
        let keep = Row(id: UUID(), hasMessages: true)
        let later = Row(id: UUID(), hasMessages: true)

        let result = ContentViewConversationListSupport.lastUsedConversation(
            from: [empty, excluded, keep, later],
            excluding: excluded.id,
            id: \.id,
            hasMessages: \.hasMessages
        )

        XCTAssertEqual(result?.id, keep.id)
        XCTAssertEqual(ContentViewConversationListSupport.lastUsedConversationFetchLimit, 8)
    }
}
