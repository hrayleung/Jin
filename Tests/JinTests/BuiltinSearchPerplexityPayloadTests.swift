import XCTest
@testable import Jin

final class BuiltinSearchPerplexityPayloadTests: XCTestCase {

    func testPerplexityBodyEmitsPreciseDateFilterReplacingRecencyFilter() {
        let body = BuiltinSearchToolHub.makePerplexityRequestBody(
            args: makeArgs(recencyDays: 7),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNil(body["search_recency_filter"],
                     "Coarse recency filter must be replaced by precise date filter.")
        XCTAssertNotNil(body["search_after_date_filter"] as? String)
    }

    func testPerplexityDateFilterFormatsAsMMDDYYYYInUTC() {
        let now = ISO8601DateFormatter().date(from: "2026-05-09T12:34:56Z")!
        let value = BuiltinSearchToolHub.perplexityDateFilter(daysAgo: 7, now: now)
        XCTAssertEqual(value, "05/02/2026")
    }

    func testPerplexityBodyEmitsCountryWhenSet() {
        let body = BuiltinSearchToolHub.makePerplexityRequestBody(
            args: makeArgs(),
            settings: makeSettings(perplexityCountry: "DE"),
            overrides: nil
        )

        XCTAssertEqual(body["country"] as? String, "DE")
    }

    func testPerplexityBodyEmitsSearchLanguageFilterAsArrayWhenSet() {
        let body = BuiltinSearchToolHub.makePerplexityRequestBody(
            args: makeArgs(),
            settings: makeSettings(perplexityLanguage: "en"),
            overrides: nil
        )

        XCTAssertEqual(body["search_language_filter"] as? [String], ["en"])
    }

    func testPerplexityBodyEmitsMaxTokensOnlyForRawContent() {
        let withRaw = BuiltinSearchToolHub.makePerplexityRequestBody(
            args: makeArgs(includeRawContent: true),
            settings: makeSettings(),
            overrides: nil
        )
        XCTAssertEqual(withRaw["max_tokens"] as? Int, 4_096)

        let withoutRaw = BuiltinSearchToolHub.makePerplexityRequestBody(
            args: makeArgs(includeRawContent: false),
            settings: makeSettings(),
            overrides: nil
        )
        XCTAssertNil(withoutRaw["max_tokens"])
    }

    func testPerplexityDomainFilterFavoursIncludeOverExclude() {
        let filter = BuiltinSearchToolHub.perplexityDomainFilter(
            includeDomains: ["a.com"],
            excludeDomains: ["b.com"]
        )

        XCTAssertEqual(filter, ["a.com"])
    }

    func testPerplexityDomainFilterFallsBackToNegatedExcludes() {
        let filter = BuiltinSearchToolHub.perplexityDomainFilter(
            includeDomains: [],
            excludeDomains: ["b.com", "c.com"]
        )

        XCTAssertEqual(filter, ["-b.com", "-c.com"])
    }

    // MARK: - Fixtures

    private func makeArgs(
        recencyDays: Int? = nil,
        includeRawContent: Bool = false
    ) -> BuiltinSearchToolHub.ResolvedArguments {
        BuiltinSearchToolHub.ResolvedArguments(
            query: "swift",
            maxResults: 8,
            recencyDays: recencyDays,
            includeRawContent: includeRawContent,
            fetchPageContent: false,
            includeDomains: [],
            excludeDomains: []
        )
    }

    private func makeSettings(
        perplexityCountry: String? = nil,
        perplexityLanguage: String? = nil
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .perplexity,
            defaultMaxResults: 8,
            defaultRecencyDays: nil,
            exaAPIKey: "",
            braveAPIKey: "",
            jinaAPIKey: "",
            firecrawlAPIKey: "",
            exaSearchType: nil,
            exaCategory: nil,
            exaUserLocation: nil,
            exaModeration: false,
            braveCountry: nil,
            braveLanguage: nil,
            braveSafesearch: nil,
            jinaReadPages: false,
            jinaCountry: nil,
            jinaLocale: nil,
            firecrawlExtractContent: false,
            firecrawlCountry: nil,
            firecrawlLanguage: nil,
            firecrawlSources: [],
            tavilyAPIKey: "",
            perplexityAPIKey: "",
            tavilySearchDepth: nil,
            tavilyTopic: nil,
            tavilyCountry: nil,
            tavilyAutoParameters: false,
            perplexityCountry: perplexityCountry,
            perplexityLanguage: perplexityLanguage
        )
    }
}
