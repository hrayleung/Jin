import XCTest
@testable import Jin

final class AddModelSheetSupportTests: XCTestCase {
    func testNormalizedNicknameTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            AddModelSheetSupport.normalizedNickname(" \n My GPT\t "),
            "My GPT"
        )
    }

    func testNormalizedModelIDTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            AddModelSheetSupport.normalizedModelID(" \n gpt-5.2-codex\t "),
            "gpt-5.2-codex"
        )
    }

    func testResolvedModelNameUsesTrimmedNicknameWhenPresent() {
        XCTAssertEqual(
            AddModelSheetSupport.resolvedModelName(
                nickname: " \n Research Model\t ",
                modelID: " gpt-5.2-codex "
            ),
            "Research Model"
        )
    }

    func testResolvedModelNameFallsBackToTrimmedModelIDWhenNicknameIsBlank() {
        XCTAssertEqual(
            AddModelSheetSupport.resolvedModelName(
                nickname: " \n\t ",
                modelID: " gpt-5.2-codex "
            ),
            "gpt-5.2-codex"
        )
    }

    func testCanAddModelRequiresNonEmptyTrimmedModelID() {
        XCTAssertTrue(AddModelSheetSupport.canAddModel(modelID: " gpt-5.2-codex "))
        XCTAssertFalse(AddModelSheetSupport.canAddModel(modelID: " \n\t "))
    }
}
