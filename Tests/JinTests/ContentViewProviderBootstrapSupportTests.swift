import XCTest
@testable import Jin

final class ContentViewProviderBootstrapSupportTests: XCTestCase {
    func testDefaultIconIDIfNeededReturnsNilForCustomIconID() {
        XCTAssertNil(
            ContentViewProviderBootstrapSupport.defaultIconIDIfNeeded(
                currentIconID: " CustomIcon ",
                providerType: .openai
            )
        )
    }

    func testDefaultIconIDIfNeededReturnsProviderDefaultForNilAndBlankIconID() {
        XCTAssertEqual(
            ContentViewProviderBootstrapSupport.defaultIconIDIfNeeded(
                currentIconID: nil,
                providerType: .anthropic
            ),
            LobeProviderIconCatalog.defaultIconID(for: .anthropic)
        )
        XCTAssertEqual(
            ContentViewProviderBootstrapSupport.defaultIconIDIfNeeded(
                currentIconID: " \n\t ",
                providerType: .openai
            ),
            LobeProviderIconCatalog.defaultIconID(for: .openai)
        )
    }

    func testDefaultIconIDIfNeededReturnsNilForUnknownProviderType() {
        XCTAssertNil(
            ContentViewProviderBootstrapSupport.defaultIconIDIfNeeded(
                currentIconID: nil,
                providerType: nil
            )
        )
    }
}
