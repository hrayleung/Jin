import XCTest
@testable import Jin

final class OpenRouterProviderSupportTests: XCTestCase {
    func testNormalizedBaseURLUsesDefaultForMissingValues() {
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL(nil),
            "https://openrouter.ai/api/v1"
        )
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("  "),
            "https://openrouter.ai/api/v1"
        )
    }

    func testNormalizedBaseURLAddsOpenRouterAPIPath() {
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("https://openrouter.ai"),
            "https://openrouter.ai/api/v1"
        )
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("https://openrouter.ai/"),
            "https://openrouter.ai/api/v1"
        )
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("https://openrouter.ai/api"),
            "https://openrouter.ai/api/v1"
        )
    }

    func testNormalizedBaseURLPreservesVersionedAndCustomBaseURLs() {
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL(" https://openrouter.ai/api/v1/ "),
            "https://openrouter.ai/api/v1"
        )
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("https://openrouter.ai/v1"),
            "https://openrouter.ai/v1"
        )
        XCTAssertEqual(
            OpenRouterProviderSupport.normalizedBaseURL("https://proxy.example.com/openrouter"),
            "https://proxy.example.com/openrouter"
        )
    }

    func testOpenRouterHeadersIncludeAppIdentityAndAuthorization() {
        XCTAssertEqual(
            OpenRouterProviderSupport.appIdentityHeaders,
            [
                "HTTP-Referer": "https://jin.app",
                "X-Title": "Jin"
            ]
        )

        let headers = OpenRouterProviderSupport.authorizedHeaders(apiKey: "test-key")
        XCTAssertEqual(headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertEqual(headers["HTTP-Referer"], "https://jin.app")
        XCTAssertEqual(headers["X-Title"], "Jin")
    }

    func testOpenRouterOCRClientDefaultBaseURLUsesSharedProviderDefault() {
        XCTAssertEqual(
            OpenRouterOCRClient.Constants.defaultBaseURL.absoluteString,
            OpenRouterProviderSupport.defaultBaseURL
        )
    }

    func testOpenRouterOCRModelCatalogTrimsAndDefaultsModelIDs() {
        XCTAssertNil(OpenRouterOCRModelCatalog.entry(for: "  "))
        XCTAssertEqual(
            OpenRouterOCRModelCatalog.entry(for: " baidu/qianfan-ocr-fast:free ")?.id,
            "baidu/qianfan-ocr-fast:free"
        )
        XCTAssertEqual(
            OpenRouterOCRModelCatalog.normalizedModelID(" missing "),
            OpenRouterOCRModelCatalog.defaultModelID
        )
    }

    func testTrustedURLAcceptsSameOriginAndDefaultHTTPSPort() throws {
        let url = try XCTUnwrap(URL(string: "https://proxy.example.com/openrouter/v1/videos/job-1"))

        XCTAssertTrue(
            OpenRouterProviderSupport.isTrustedURL(
                url,
                forBaseURL: "https://proxy.example.com:443/openrouter/v1"
            )
        )
    }

    func testTrustedURLRejectsDifferentHostAndScheme() throws {
        let baseURL = "https://proxy.example.com/openrouter/v1"
        let differentHost = try XCTUnwrap(URL(string: "https://evil.example.com/openrouter/v1/videos/job-1"))
        let differentScheme = try XCTUnwrap(URL(string: "http://proxy.example.com/openrouter/v1/videos/job-1"))

        XCTAssertFalse(OpenRouterProviderSupport.isTrustedURL(differentHost, forBaseURL: baseURL))
        XCTAssertFalse(OpenRouterProviderSupport.isTrustedURL(differentScheme, forBaseURL: baseURL))
    }

    func testTrustedURLMatchesExplicitAndImplicitPorts() throws {
        let implicitHTTP = try XCTUnwrap(URL(string: "http://localhost/openrouter/v1/videos/job-1"))
        let explicitHTTP = try XCTUnwrap(URL(string: "http://localhost:80/openrouter/v1/videos/job-1"))
        let explicitHTTPS = try XCTUnwrap(URL(string: "https://openrouter.ai:443/api/v1/videos/job-1"))

        XCTAssertTrue(
            OpenRouterProviderSupport.isTrustedURL(
                implicitHTTP,
                forBaseURL: "http://localhost:80/openrouter/v1"
            )
        )
        XCTAssertTrue(
            OpenRouterProviderSupport.isTrustedURL(
                explicitHTTP,
                forBaseURL: "http://localhost/openrouter/v1"
            )
        )
        XCTAssertTrue(
            OpenRouterProviderSupport.isTrustedURL(
                explicitHTTPS,
                forBaseURL: "https://openrouter.ai/api/v1"
            )
        )
    }

    func testTrustedURLRejectsUnsupportedSchemeAndPortMismatch() throws {
        let unsupportedScheme = try XCTUnwrap(URL(string: "ftp://proxy.example.com/openrouter/v1/videos/job-1"))
        let portMismatch = try XCTUnwrap(URL(string: "https://proxy.example.com:8443/openrouter/v1/videos/job-1"))

        XCTAssertFalse(
            OpenRouterProviderSupport.isTrustedURL(
                unsupportedScheme,
                forBaseURL: "https://proxy.example.com/openrouter/v1"
            )
        )
        XCTAssertFalse(
            OpenRouterProviderSupport.isTrustedURL(
                portMismatch,
                forBaseURL: "https://proxy.example.com/openrouter/v1"
            )
        )
    }
}
