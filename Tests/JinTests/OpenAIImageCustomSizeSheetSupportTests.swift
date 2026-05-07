import XCTest
@testable import Jin

final class OpenAIImageCustomSizeSheetSupportTests: XCTestCase {
    func testInitialDraftTextUsesExistingNonAutoSize() {
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.initialDraftText(
                currentSize: OpenAIImageSize(rawValue: " 2048X1152 ")
            ),
            "2048x1152"
        )
    }

    func testInitialDraftTextClearsAutoOrMissingSize() {
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.initialDraftText(currentSize: .auto),
            ""
        )
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.initialDraftText(currentSize: nil),
            ""
        )
    }

    func testParsedSizeNormalizesDraftAndDropsBlankDraft() {
        XCTAssertNil(OpenAIImageCustomSizeSheetSupport.parsedSize(from: " \n\t "))
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.parsedSize(from: " 2048X1152 ")?.rawValue,
            "2048x1152"
        )
    }

    func testDisplayedValidationErrorSuppressesBlankDraftUntilExplicitSubmitError() {
        XCTAssertNil(
            OpenAIImageCustomSizeSheetSupport.displayedValidationError(
                explicitError: nil,
                draftText: " \n ",
                modelID: "gpt-image-2"
            )
        )

        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.displayedValidationError(
                explicitError: OpenAIImageCustomSizeSheetSupport.invalidSizeMessage,
                draftText: " \n ",
                modelID: "gpt-image-2"
            ),
            OpenAIImageCustomSizeSheetSupport.invalidSizeMessage
        )
    }

    func testValidationUsesImageModelSizeRules() {
        XCTAssertNil(
            OpenAIImageCustomSizeSheetSupport.validationError(
                draftText: "2048x1152",
                modelID: "gpt-image-2"
            )
        )
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.validationError(
                draftText: "1025x1025",
                modelID: "gpt-image-2"
            ),
            "Width and height must both be multiples of 16."
        )
        XCTAssertEqual(
            OpenAIImageCustomSizeSheetSupport.validationError(
                draftText: "2048x1152",
                modelID: "gpt-image-1"
            ),
            "Unsupported size for GPT Image 1."
        )
    }

    func testCanSubmitOnlyRequiresNonblankDraft() {
        XCTAssertFalse(OpenAIImageCustomSizeSheetSupport.canSubmit(draftText: " \n "))
        XCTAssertTrue(OpenAIImageCustomSizeSheetSupport.canSubmit(draftText: "1024xx1024"))
    }
}
