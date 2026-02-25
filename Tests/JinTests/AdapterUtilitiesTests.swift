import Foundation
import XCTest
@testable import Jin

final class AdapterUtilitiesTests: XCTestCase {
    func testValidatedURLAcceptsSupportedAbsoluteSchemes() throws {
        let httpsURL = try validatedURL("https://api.example.com/v1")
        XCTAssertEqual(httpsURL.scheme, "https")
        XCTAssertEqual(httpsURL.host, "api.example.com")

        let wssURL = try validatedURL("wss://api.example.com/v1")
        XCTAssertEqual(wssURL.scheme, "wss")
        XCTAssertEqual(wssURL.host, "api.example.com")
    }

    func testValidatedURLRejectsRelativeEndpoint() {
        XCTAssertThrowsError(try validatedURL("api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("must be absolute"))
        }
    }

    func testValidatedURLRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try validatedURL("ftp://api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("Invalid URL scheme"))
        }
    }
}
