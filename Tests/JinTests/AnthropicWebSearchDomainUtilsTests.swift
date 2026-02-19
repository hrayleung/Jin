import XCTest
@testable import Jin

final class AnthropicWebSearchDomainUtilsTests: XCTestCase {
    func testSplitInputSupportsCommaAndNewline() {
        let parsed = AnthropicWebSearchDomainUtils.splitInput("example.com,\nfoo.com\nbar.com")
        XCTAssertEqual(parsed, ["example.com", "foo.com", "bar.com"])
    }

    func testNormalizedDomainsDeduplicatesCaseInsensitiveEntries() {
        let normalized = AnthropicWebSearchDomainUtils.normalizedDomains([
            " example.com ",
            "Example.com",
            "docs.example.com"
        ])
        XCTAssertEqual(normalized, ["example.com", "docs.example.com"])
    }

    func testValidationRejectsScheme() {
        let error = AnthropicWebSearchDomainUtils.validationError(for: "https://example.com")
        XCTAssertNotNil(error)
    }

    func testValidationRejectsWildcardInHost() {
        let error = AnthropicWebSearchDomainUtils.validationError(for: "*.example.com")
        XCTAssertNotNil(error)
    }

    func testValidationRejectsMultipleWildcards() {
        let error = AnthropicWebSearchDomainUtils.validationError(for: "example.com/*/news/*")
        XCTAssertNotNil(error)
    }

    func testValidationAcceptsSingleWildcardInPath() {
        let error = AnthropicWebSearchDomainUtils.validationError(for: "example.com/*/articles")
        XCTAssertNil(error)
    }
}
