import XCTest
@testable import Jin

final class ModelSettingsSheetSupportTests: XCTestCase {
    func testReenablingReasoningAfterPersistedOffOverrideHasAnEditableMode() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.editableReasoningType(for: ModelReasoningConfig(type: .none)),
            .effort
        )
        XCTAssertEqual(ModelSettingsSheetSupport.editableReasoningType(for: nil), .effort)
    }

    func testReasoningEditorPreservesConfiguredModes() {
        for type in [ReasoningConfigType.effort, .budget, .toggle] {
            XCTAssertEqual(
                ModelSettingsSheetSupport.editableReasoningType(for: ModelReasoningConfig(type: type)), type
            )
        }
    }

    func testPositiveIntegerParsesTrimmedPositiveInteger() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.positiveInteger(from: " \n 128000\t "),
            128_000
        )
    }

    func testPositiveIntegerRejectsBlankZeroNegativeAndNonIntegerDrafts() {
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: " \n\t "))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "0"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "-1"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "1.5"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "many"))
    }

    func testOptionalPositiveIntegerReturnsEmptyForBlankDraft() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.optionalPositiveInteger(from: " \n\t "),
            .empty
        )
    }

    func testOptionalPositiveIntegerParsesTrimmedPositiveInteger() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.optionalPositiveInteger(from: " \n 4096\t "),
            .value(4_096)
        )
    }

    func testOptionalPositiveIntegerRejectsInvalidValues() {
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "0"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "-1"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "1.5"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "many"), .invalid)
    }
}
