import XCTest
@testable import Jin

final class AssistantSettingsEditorSupportTests: XCTestCase {
    func testNormalizedCustomReplyLanguageTrimsAndDropsBlankInput() {
        XCTAssertEqual(
            AssistantSettingsEditorSupport.normalizedCustomReplyLanguage(" \n Klingon\t "),
            "Klingon"
        )
        XCTAssertNil(AssistantSettingsEditorSupport.normalizedCustomReplyLanguage(" \n\t "))
    }

    func testNormalizedAssistantDescriptionTrimsAndDropsBlankInput() {
        XCTAssertEqual(
            AssistantSettingsEditorSupport.normalizedAssistantDescription(" \n General assistant\t "),
            "General assistant"
        )
        XCTAssertNil(AssistantSettingsEditorSupport.normalizedAssistantDescription(" \n\t "))
    }

    func testNormalizedIconTrimsAndDropsBlankInput() {
        XCTAssertEqual(
            AssistantSettingsEditorSupport.normalizedIcon(" \n sparkles\t "),
            "sparkles"
        )
        XCTAssertNil(AssistantSettingsEditorSupport.normalizedIcon(" \n\t "))
    }

    func testOptionalPositiveIntegerDraftClearsBlankInput() {
        XCTAssertEqual(
            AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: " \n\t "),
            .clear
        )
    }

    func testOptionalPositiveIntegerDraftParsesTrimmedPositiveInteger() {
        XCTAssertEqual(
            AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: " \n 2048\t "),
            .value(2_048)
        )
    }

    func testOptionalPositiveIntegerDraftRejectsInvalidValues() {
        XCTAssertEqual(AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: "0"), .invalid)
        XCTAssertEqual(AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: "-1"), .invalid)
        XCTAssertEqual(AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: "1.5"), .invalid)
        XCTAssertEqual(AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: "many"), .invalid)
    }
}
