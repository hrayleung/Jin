import XCTest
@testable import Jin

final class AssistantReplyLanguageOptionTests: XCTestCase {
    func testResolvedReturnsDefaultForNilAndBlankLanguages() {
        XCTAssertEqual(AssistantReplyLanguageOption.resolved(from: nil), .default)
        XCTAssertEqual(AssistantReplyLanguageOption.resolved(from: " \n\t "), .default)
    }

    func testResolvedTrimsPresetLanguageBeforeMatching() {
        XCTAssertEqual(
            AssistantReplyLanguageOption.resolved(from: " \n English\t "),
            .english
        )
    }

    func testResolvedReturnsCustomForTrimmedUnknownLanguage() {
        XCTAssertEqual(
            AssistantReplyLanguageOption.resolved(from: " \n Klingon\t "),
            .custom
        )
    }
}
