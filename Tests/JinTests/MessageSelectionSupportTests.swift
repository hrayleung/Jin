import XCTest
@testable import Jin

final class MessageSelectionSupportTests: XCTestCase {
    func testNormalizedSelectedTextTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            MessageSelectionSupport.normalizedSelectedText(" \n Selected answer\t "),
            "Selected answer"
        )
    }

    func testNormalizedSelectedTextRejectsBlankSelection() {
        XCTAssertNil(MessageSelectionSupport.normalizedSelectedText(" \n\t "))
    }

    func testSelectionIsEmptyFollowsNormalizedSelectedText() {
        XCTAssertTrue(MessageSelectionSupport.selectionIsEmpty(" \n\t "))
        XCTAssertFalse(MessageSelectionSupport.selectionIsEmpty(" Selected "))
    }
}
