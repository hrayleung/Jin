import XCTest
@testable import Jin

final class BuiltinSearchFirecrawlPayloadTests: XCTestCase {

    // MARK: - Country

    func testFirecrawlBodyUsesFirecrawlCountryNotBraveCountry() throws {
        let settings = makeSettings(braveCountry: "US", firecrawlCountry: "DE")

        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: settings,
            overrides: nil
        )

        XCTAssertEqual(body["country"] as? String, "DE",
                       "Firecrawl must read its own country pref, not Brave's.")
    }

    func testFirecrawlBodyOmitsCountryWhenOnlyBraveCountrySet() throws {
        let settings = makeSettings(braveCountry: "US", firecrawlCountry: nil)

        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: settings,
            overrides: nil
        )

        XCTAssertNil(body["country"], "Brave country must not bleed into Firecrawl.")
    }

    func testFirecrawlBodyHonoursOverrideCountry() {
        let settings = makeSettings(firecrawlCountry: "DE")
        let overrides = SearchPluginControls(firecrawlCountry: "JP")

        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: settings,
            overrides: overrides
        )

        XCTAssertEqual(body["country"] as? String, "JP")
    }

    // MARK: - Domain operators

    func testFirecrawlBodyAugmentsQueryWithSiteOperators() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(
                query: "swift concurrency",
                includeDomains: ["apple.com", "swift.org"],
                excludeDomains: ["medium.com"]
            ),
            settings: makeSettings(),
            overrides: nil
        )

        let augmented = body["query"] as? String
        XCTAssertEqual(augmented, "swift concurrency (site:apple.com OR site:swift.org) -site:medium.com")
    }

    func testFirecrawlBodyOmitsParensForSingleIncludeDomain() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift", includeDomains: ["apple.com"]),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["query"] as? String, "swift site:apple.com")
    }

    func testFirecrawlBodyDoesNotAugmentWhenNoDomainFilters() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["query"] as? String, "swift")
    }

    // MARK: - Sources

    func testFirecrawlBodyOmitsSourcesWhenUnset() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNil(body["sources"])
    }

    func testFirecrawlBodyEncodesSourcesAsTypeObjects() {
        let settings = makeSettings(firecrawlSources: [.web, .news])

        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: settings,
            overrides: nil
        )

        let sources = try? XCTUnwrap(body["sources"] as? [[String: String]])
        XCTAssertEqual(sources, [["type": "web"], ["type": "news"]])
    }

    // MARK: - Defensive flags

    func testFirecrawlBodyAlwaysSendsIgnoreInvalidURLs() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["ignoreInvalidURLs"] as? Bool, true)
    }

    func testFirecrawlBodyIncludesLanguageWhenSet() {
        let settings = makeSettings(firecrawlLanguage: "en")

        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift"),
            settings: settings,
            overrides: nil
        )

        XCTAssertEqual(body["lang"] as? String, "en")
    }

    func testFirecrawlBodyMapsRecencyDaysToTBS() {
        let body = BuiltinSearchToolHub.makeFirecrawlRequestBody(
            args: makeArgs(query: "swift", recencyDays: 7),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["tbs"] as? String, "qdr:w")
    }

    // MARK: - Result mapping

    func testFirecrawlRowsDeduplicateByURLBeforeApplyingCap() {
        let rows = BuiltinSearchToolHub.makeFirecrawlRows(
            from: [
                ["url": "https://example.com/a", "title": "A"],
                ["url": "https://example.com/a", "title": "A duplicate"],
                ["url": "https://example.com/b", "title": "B"]
            ],
            maxResults: 2
        )

        XCTAssertEqual(rows.map(\.url), ["https://example.com/a", "https://example.com/b"])
    }

    func testFirecrawlRowsUseImageURLWhenURLIsMissing() {
        let rows = BuiltinSearchToolHub.makeFirecrawlRows(
            from: [
                ["imageUrl": "https://example.com/image.png", "title": "Image"]
            ],
            maxResults: 1
        )

        XCTAssertEqual(rows.first?.url, "https://example.com/image.png")
        XCTAssertEqual(rows.first?.source, "example.com")
    }

    // MARK: - Fixtures

    private func makeArgs(
        query: String,
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
        braveCountry: String? = nil,
        firecrawlCountry: String? = nil,
        firecrawlLanguage: String? = nil,
        firecrawlSources: [FirecrawlSourceKind] = [],
        firecrawlExtractContent: Bool = false
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .firecrawl,
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
            braveCountry: braveCountry,
            braveLanguage: nil,
            braveSafesearch: nil,
            jinaReadPages: false,
            jinaCountry: nil,
            jinaLocale: nil,
            firecrawlExtractContent: firecrawlExtractContent,
            firecrawlCountry: firecrawlCountry,
            firecrawlLanguage: firecrawlLanguage,
            firecrawlSources: firecrawlSources,
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
