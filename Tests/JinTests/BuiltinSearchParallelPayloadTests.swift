import XCTest
@testable import Jin

final class BuiltinSearchParallelPayloadTests: XCTestCase {
    func testSearchBodyUsesObjectiveKeywordQueriesFastModeAndMaxResults() throws {
        let body = BuiltinSearchToolHub.makeParallelSearchRequestBody(
            args: makeArgs(maxResults: 8),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["mode"] as? String, "fast")
        XCTAssertEqual(body["search_queries"] as? [String], ["swift concurrency"])
        XCTAssertEqual(
            body["objective"] as? String,
            "Find current, cited web information about: swift concurrency"
        )

        let advanced = try XCTUnwrap(body["advanced_settings"] as? [String: Any])
        XCTAssertEqual(advanced["max_results"] as? Int, 8)
        XCTAssertNil(advanced["location"])
        XCTAssertNil(advanced["source_policy"])
    }

    func testSearchBodyClampsMaxResultsToParallelCap() throws {
        let body = BuiltinSearchToolHub.makeParallelSearchRequestBody(
            args: makeArgs(maxResults: 50),
            settings: makeSettings(),
            overrides: nil
        )

        let advanced = try XCTUnwrap(body["advanced_settings"] as? [String: Any])
        XCTAssertEqual(advanced["max_results"] as? Int, 20)
    }

    func testSearchBodyPrefersOverrideModeAndNormalizesLocation() throws {
        let body = BuiltinSearchToolHub.makeParallelSearchRequestBody(
            args: makeArgs(),
            settings: makeSettings(mode: .basic, location: "UK"),
            overrides: SearchPluginControls(parallelSearchMode: .turbo)
        )

        XCTAssertEqual(body["mode"] as? String, "turbo")
        let advanced = try XCTUnwrap(body["advanced_settings"] as? [String: Any])
        XCTAssertEqual(advanced["location"] as? String, "gb")
    }

    func testSearchBodyOmitsUnsupportedLocation() throws {
        let body = BuiltinSearchToolHub.makeParallelSearchRequestBody(
            args: makeArgs(),
            settings: makeSettings(location: "zz"),
            overrides: nil
        )

        let advanced = try XCTUnwrap(body["advanced_settings"] as? [String: Any])
        XCTAssertNil(advanced["location"])
    }

    func testSourcePolicyMapsDomainsAndRecencyToAfterDate() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z")!
        let policy = try XCTUnwrap(
            BuiltinSearchToolHub.parallelSourcePolicy(
                includeDomains: ["docs.parallel.ai", " "],
                excludeDomains: ["reddit.com"],
                recencyDays: 7,
                now: now
            )
        )

        XCTAssertEqual(policy["include_domains"] as? [String], ["docs.parallel.ai"])
        XCTAssertEqual(policy["exclude_domains"] as? [String], ["reddit.com"])
        XCTAssertEqual(policy["after_date"] as? String, "2026-08-23")
    }

    func testExtractBodyReusesObjectiveQueriesAndSession() {
        let body = BuiltinSearchToolHub.makeParallelExtractRequestBody(
            urls: ["https://example.com/one", "https://example.com/two"],
            query: "swift concurrency",
            sessionID: "session_abc"
        )

        XCTAssertEqual(body["urls"] as? [String], [
            "https://example.com/one",
            "https://example.com/two"
        ])
        XCTAssertEqual(body["search_queries"] as? [String], ["swift concurrency"])
        XCTAssertEqual(body["session_id"] as? String, "session_abc")
        XCTAssertEqual(
            body["objective"] as? String,
            "Find current, cited web information about: swift concurrency"
        )
    }

    func testCitationRowJoinsExcerptsAndKeepsPublishDate() throws {
        let row = try XCTUnwrap(
            BuiltinSearchToolHub.makeParallelCitationRow(from: [
                "url": "https://parallel.ai/",
                "title": "Parallel",
                "publish_date": "2026-08-01",
                "excerpts": ["First excerpt", "Second excerpt"]
            ])
        )

        XCTAssertEqual(row.url, "https://parallel.ai/")
        XCTAssertEqual(row.title, "Parallel")
        XCTAssertEqual(row.publishedAt, "2026-08-01")
        XCTAssertEqual(row.snippet, "First excerpt\n\nSecond excerpt")
        XCTAssertEqual(row.source, "parallel.ai")
    }

    func testMergeExtractedContentPrefersExcerptsOverOriginalSnippet() {
        let rows = [
            SearchCitationRow(
                title: "One",
                url: "https://example.com/one",
                snippet: "short",
                publishedAt: nil,
                source: "example.com"
            )
        ]
        let merged = BuiltinSearchToolHub.mergeParallelExtractedContent(
            rows: rows,
            extractResults: [[
                "url": "https://example.com/one",
                "excerpts": ["longer markdown excerpt"]
            ]]
        )

        XCTAssertEqual(merged.first?.snippet, "longer markdown excerpt")
    }

    func testSearchQueriesFallBackForBlankInput() {
        XCTAssertEqual(BuiltinSearchToolHub.parallelSearchQueries(from: "  "), ["web search"])
        XCTAssertTrue(
            BuiltinSearchToolHub.parallelObjective(from: "  ")
                .contains("Find current, cited web information")
        )
    }

    func testSearchBodyPrefersExplicitObjectiveAndSearchQueries() throws {
        let args = BuiltinSearchToolHub.ResolvedArguments(
            query: "fallback query",
            maxResults: 8,
            recencyDays: nil,
            includeRawContent: false,
            fetchPageContent: false,
            includeDomains: [],
            excludeDomains: [],
            objective: "Find recent Parallel Search API changes.",
            searchQueries: ["Parallel Search API", "Parallel extract excerpts"]
        )
        let body = BuiltinSearchToolHub.makeParallelSearchRequestBody(
            args: args,
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["objective"] as? String, "Find recent Parallel Search API changes.")
        XCTAssertEqual(body["search_queries"] as? [String], [
            "Parallel Search API",
            "Parallel extract excerpts"
        ])
    }

    // MARK: - Fixtures

    private func makeArgs(maxResults: Int = 8) -> BuiltinSearchToolHub.ResolvedArguments {
        BuiltinSearchToolHub.ResolvedArguments(
            query: "swift concurrency",
            maxResults: maxResults,
            recencyDays: nil,
            includeRawContent: false,
            fetchPageContent: false,
            includeDomains: [],
            excludeDomains: [],
            objective: nil,
            searchQueries: []
        )
    }

    private func makeSettings(
        mode: ParallelSearchMode? = nil,
        location: String? = nil
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .parallel,
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
            perplexityCountry: nil,
            perplexityLanguage: nil,
            parallelAPIKey: "",
            parallelSearchMode: mode,
            parallelLocation: location,
            parallelExtractPages: false
        )
    }
}
