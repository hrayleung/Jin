import XCTest
@testable import Jin

final class BuiltinSearchJinaRequestTests: XCTestCase {

    func testJinaRequestUsesPOSTToCanonicalEndpoint() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://s.jina.ai/")
    }

    func testJinaRequestSetsBearerAuthAndJSONContentType() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(),
            settings: makeSettings(),
            apiKey: "abc123"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testJinaRequestSendsNoContentHeaderWhenFetchPageContentDisabled() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(fetchPageContent: false),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Respond-With"), "no-content",
                       "Fast path should request a content-free response.")
    }

    func testJinaRequestOmitsNoContentHeaderWhenFetchPageContentEnabled() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(fetchPageContent: true),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "X-Respond-With"))
    }

    func testJinaRequestSendsLinksAndAltHeadersForRawContent() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(includeRawContent: true),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-With-Generated-Alt"), "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-With-Links-Summary"), "true")
    }

    func testJinaRequestSetsXSiteForFirstIncludeDomain() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(includeDomains: ["apple.com", "swift.org"]),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Site"), "apple.com")
    }

    func testJinaRequestAppendsRemainingIncludeDomainsToBodyQuery() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(query: "swift", includeDomains: ["apple.com", "swift.org", "kavsoft.dev"]),
            settings: makeSettings(),
            apiKey: "key"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let q = try XCTUnwrap(json?["q"] as? String)
        XCTAssertEqual(q, "swift site:swift.org OR site:kavsoft.dev")
    }

    func testJinaRequestUsesCleanQueryWhenNoIncludeDomains() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(query: "swift"),
            settings: makeSettings(),
            apiKey: "key"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["q"] as? String, "swift")
    }

    func testJinaRequestCarriesLocaleAndCountryWhenSet() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(),
            settings: makeSettings(jinaCountry: "DE", jinaLocale: "de-DE"),
            apiKey: "key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Locale"), "de-DE")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Country"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["gl"] as? String, "DE")
    }

    func testJinaRequestUsesBrowserEngineByDefault() throws {
        let request = try BuiltinSearchToolHub.makeJinaRequest(
            args: makeArgs(),
            settings: makeSettings(),
            apiKey: "key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Engine"), "browser")
    }

    // MARK: - Response parsing

    func testJinaResponseExtractorHandlesDataKey() {
        let response: [String: Any] = [
            "data": [
                ["url": "https://a.com", "title": "A", "content": "..."]
            ]
        ]

        let results = BuiltinSearchToolHub.extractJinaResults(from: response)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["url"] as? String, "https://a.com")
    }

    func testJinaResponseExtractorHandlesBareArray() {
        let response: [[String: Any]] = [["url": "https://a.com"]]
        let results = BuiltinSearchToolHub.extractJinaResults(from: response)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Fixtures

    private func makeArgs(
        query: String = "swift",
        fetchPageContent: Bool = false,
        includeRawContent: Bool = false,
        includeDomains: [String] = []
    ) -> BuiltinSearchToolHub.ResolvedArguments {
        BuiltinSearchToolHub.ResolvedArguments(
            query: query,
            maxResults: 5,
            recencyDays: nil,
            includeRawContent: includeRawContent,
            fetchPageContent: fetchPageContent,
            includeDomains: includeDomains,
            excludeDomains: []
        )
    }

    private func makeSettings(
        jinaCountry: String? = nil,
        jinaLocale: String? = nil
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .jina,
            defaultMaxResults: 5,
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
            jinaCountry: jinaCountry,
            jinaLocale: jinaLocale,
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
