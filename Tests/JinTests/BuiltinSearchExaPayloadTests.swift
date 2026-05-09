import XCTest
@testable import Jin

final class BuiltinSearchExaPayloadTests: XCTestCase {

    // MARK: - Search type

    func testExaBodyEmitsNewDeepLiteSearchType() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaSearchType: .deepLite),
            overrides: nil
        )

        XCTAssertEqual(body["type"] as? String, "deep-lite")
    }

    func testExaBodyEmitsNewDeepReasoningSearchType() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaSearchType: .deepReasoning),
            overrides: nil
        )

        XCTAssertEqual(body["type"] as? String, "deep-reasoning")
    }

    // MARK: - Category / userLocation / moderation

    func testExaBodyOmitsOptionalFieldsByDefault() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNil(body["category"])
        XCTAssertNil(body["userLocation"])
        XCTAssertNil(body["moderation"])
    }

    func testExaBodyEmitsCategoryWhenSetInSettings() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaCategory: "research paper"),
            overrides: nil
        )

        XCTAssertEqual(body["category"] as? String, "research paper")
    }

    func testExaBodyOverrideCategoryWinsOverSettings() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaCategory: "company"),
            overrides: SearchPluginControls(exaCategory: "people")
        )

        XCTAssertEqual(body["category"] as? String, "people")
    }

    func testExaBodyDropsUnknownCategory() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaCategory: "garbage"),
            overrides: nil
        )

        XCTAssertNil(body["category"], "Invalid categories must be silently dropped to avoid 400s.")
    }

    func testExaBodyEmitsUserLocation() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaUserLocation: "DE"),
            overrides: nil
        )

        XCTAssertEqual(body["userLocation"] as? String, "DE")
    }

    func testExaBodyEmitsModerationWhenEnabled() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(exaModeration: true),
            overrides: nil
        )

        XCTAssertEqual(body["moderation"] as? Bool, true)
    }

    // MARK: - Structured contents

    func testExaBodyOmitsContentsByDefault() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNil(body["contents"])
    }

    func testExaBodyEmitsStructuredContentsWhenIncludeRawContent() throws {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(includeRawContent: true),
            settings: makeSettings(),
            overrides: nil
        )

        let contents = try XCTUnwrap(body["contents"] as? [String: Any])
        let text = try XCTUnwrap(contents["text"] as? [String: Any])
        XCTAssertEqual(text["maxCharacters"] as? Int, 8_000)
        XCTAssertEqual(text["verbosity"] as? String, "compact")
        XCTAssertNil(text["maxAgeHours"])
    }

    func testExaBodyEmitsMaxAgeHoursDerivedFromRecency() throws {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(recencyDays: 7, includeRawContent: true),
            settings: makeSettings(),
            overrides: nil
        )

        let contents = try XCTUnwrap(body["contents"] as? [String: Any])
        let text = try XCTUnwrap(contents["text"] as? [String: Any])
        XCTAssertNil(text["maxAgeHours"])
        XCTAssertEqual(contents["maxAgeHours"] as? Int, 168)
    }

    // MARK: - Recency / domains

    func testExaBodyEmitsStartPublishedDateWhenRecencySet() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(recencyDays: 30),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNotNil(body["startPublishedDate"] as? String)
    }

    func testExaBodyEmitsDomainArrays() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(includeDomains: ["a.com"], excludeDomains: ["b.com"]),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["includeDomains"] as? [String], ["a.com"])
        XCTAssertEqual(body["excludeDomains"] as? [String], ["b.com"])
    }

    func testExaBodySuppressesUnsupportedFiltersForCompanyCategory() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(
                recencyDays: 7,
                includeDomains: ["exa.ai"],
                excludeDomains: ["example.com"]
            ),
            settings: makeSettings(exaCategory: "company"),
            overrides: nil
        )

        XCTAssertEqual(body["category"] as? String, "company")
        XCTAssertEqual(body["includeDomains"] as? [String], ["exa.ai"])
        XCTAssertNil(body["excludeDomains"])
        XCTAssertNil(body["startPublishedDate"])
    }

    func testExaBodyFiltersPeopleIncludeDomainsToLinkedInAndDropsUnsupportedFilters() {
        let body = BuiltinSearchToolHub.makeExaRequestBody(
            args: makeArgs(
                recencyDays: 7,
                includeDomains: ["linkedin.com", "example.com", "www.linkedin.com"],
                excludeDomains: ["example.com"]
            ),
            settings: makeSettings(exaCategory: "people"),
            overrides: nil
        )

        XCTAssertEqual(body["category"] as? String, "people")
        XCTAssertEqual(body["includeDomains"] as? [String], ["linkedin.com", "www.linkedin.com"])
        XCTAssertNil(body["excludeDomains"])
        XCTAssertNil(body["startPublishedDate"])
    }

    // MARK: - Fixtures

    private func makeArgs(
        query: String = "swift",
        maxResults: Int = 8,
        recencyDays: Int? = nil,
        includeDomains: [String] = [],
        excludeDomains: [String] = [],
        includeRawContent: Bool = false
    ) -> BuiltinSearchToolHub.ResolvedArguments {
        BuiltinSearchToolHub.ResolvedArguments(
            query: query,
            maxResults: maxResults,
            recencyDays: recencyDays,
            includeRawContent: includeRawContent,
            fetchPageContent: false,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains
        )
    }

    private func makeSettings(
        exaSearchType: ExaSearchType? = nil,
        exaCategory: String? = nil,
        exaUserLocation: String? = nil,
        exaModeration: Bool = false
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .exa,
            defaultMaxResults: 8,
            defaultRecencyDays: nil,
            exaAPIKey: "",
            braveAPIKey: "",
            jinaAPIKey: "",
            firecrawlAPIKey: "",
            exaSearchType: exaSearchType,
            exaCategory: exaCategory,
            exaUserLocation: exaUserLocation,
            exaModeration: exaModeration,
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
            perplexityCountry: nil,
            perplexityLanguage: nil
        )
    }
}
