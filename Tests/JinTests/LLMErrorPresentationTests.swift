import XCTest
@testable import Jin

final class LLMErrorPresentationTests: XCTestCase {
    func testAuthenticationFailedDescriptionTrimsProviderMessage() {
        let error = LLMError.authenticationFailed(message: " \n expired key \t ")

        XCTAssertEqual(
            error.errorDescription,
            "Authentication failed. Please check your API key.\n\nexpired key"
        )
    }

    func testAuthenticationFailedDescriptionUsesGenericMessageForBlankProviderMessage() {
        let error = LLMError.authenticationFailed(message: " \n\t ")

        XCTAssertEqual(
            error.errorDescription,
            "Authentication failed. Please check your API key."
        )
    }
}
