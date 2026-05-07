import XCTest
@testable import Jin

final class QuoteCardPresentationSupportTests: XCTestCase {
    func testSourceLineUsesRoleLabelAndTrimmedModelName() {
        XCTAssertEqual(
            QuoteCardPresentationSupport.sourceLine(role: .assistant, modelName: " \n GPT-5\t "),
            "Assistant · GPT-5"
        )
    }

    func testSourceLineFallsBackToRoleOnlyForBlankModelName() {
        XCTAssertEqual(
            QuoteCardPresentationSupport.sourceLine(role: .user, modelName: " \n\t "),
            "User"
        )
        XCTAssertEqual(
            QuoteCardPresentationSupport.sourceLine(role: .tool, modelName: nil),
            "Tool"
        )
    }

    func testSourceLineUsesQuotedForMissingRole() {
        XCTAssertEqual(
            QuoteCardPresentationSupport.sourceLine(role: nil, modelName: "Reference"),
            "Quoted · Reference"
        )
    }
}
