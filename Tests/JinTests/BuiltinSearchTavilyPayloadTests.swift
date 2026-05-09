import XCTest
@testable import Jin

final class BuiltinSearchTavilyPayloadTests: XCTestCase {

    func testTavilyBodyOmitsCountryByDefault() {
        let body = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNil(body["country"])
    }

    func testTavilyBodyEmitsCountryOnlyForGeneralTopic() {
        let general = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilyCountry: "DE", tavilyTopic: "general"),
            overrides: nil
        )
        XCTAssertEqual(general["country"] as? String, "germany")

        let news = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilyCountry: "DE", tavilyTopic: "news"),
            overrides: nil
        )
        XCTAssertNil(news["country"], "Tavily restricts country to general topic.")
    }

    func testTavilyBodyMapsCountryNameAndDropsUnsupportedCountry() {
        let named = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilyCountry: " United States "),
            overrides: nil
        )
        XCTAssertEqual(named["country"] as? String, "united states")

        let unsupported = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilyCountry: "XX"),
            overrides: nil
        )
        XCTAssertNil(unsupported["country"])
    }

    func testTavilyBodyEmitsAutoParametersOnlyWhenEnabled() {
        let off = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(),
            overrides: nil
        )
        XCTAssertNil(off["auto_parameters"])

        let on = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilyAutoParameters: true),
            overrides: nil
        )
        XCTAssertEqual(on["auto_parameters"] as? Bool, true)
    }

    func testTavilyAutoParametersOmitDefaultedDepthTopicAndDependentFields() {
        let body = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(
                tavilyCountry: "DE",
                tavilyAutoParameters: true,
                tavilySearchDepth: "basic",
                tavilyTopic: "general"
            ),
            overrides: nil
        )

        XCTAssertEqual(body["auto_parameters"] as? Bool, true)
        XCTAssertNil(body["search_depth"])
        XCTAssertNil(body["topic"])
        XCTAssertNil(body["country"])
        XCTAssertNil(body["chunks_per_source"])
    }

    func testTavilyAutoParametersKeepExplicitDepthAndTopicOverrides() {
        let body = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(
                tavilyCountry: "DE",
                tavilyAutoParameters: true,
                tavilySearchDepth: "basic",
                tavilyTopic: "news"
            ),
            overrides: SearchPluginControls(tavilySearchDepth: "advanced", tavilyTopic: "general")
        )

        XCTAssertEqual(body["search_depth"] as? String, "advanced")
        XCTAssertEqual(body["topic"] as? String, "general")
        XCTAssertEqual(body["country"] as? String, "germany")
        XCTAssertEqual(body["chunks_per_source"] as? Int, 3)
    }

    func testTavilyBodyEmitsChunksPerSourceForAdvancedDepth() {
        let advanced = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilySearchDepth: "advanced"),
            overrides: nil
        )
        XCTAssertEqual(advanced["chunks_per_source"] as? Int, 3)

        let basic = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(tavilySearchDepth: "basic"),
            overrides: nil
        )
        XCTAssertNil(basic["chunks_per_source"])
    }

    func testTavilyBodyEmitsStartAndEndDatesForRecency() {
        let body = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(recencyDays: 7),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertNotNil(body["start_date"] as? String)
        XCTAssertNotNil(body["end_date"] as? String)
        XCTAssertNil(body["time_range"], "time_range branch is dead after recency cleanup.")
    }

    func testTavilyBodyDefaultsTopicToGeneralAndDepthToBasic() {
        let body = BuiltinSearchToolHub.makeTavilyRequestBody(
            args: makeArgs(),
            settings: makeSettings(),
            overrides: nil
        )

        XCTAssertEqual(body["topic"] as? String, "general")
        XCTAssertEqual(body["search_depth"] as? String, "basic")
    }

    func testTavilyDepthValueNormalizesUltraFast() {
        XCTAssertEqual(BuiltinSearchToolHub.tavilyDepthValue("ultra-fast"), "ultra-fast")
        XCTAssertEqual(BuiltinSearchToolHub.tavilyDepthValue("ultra_fast"), "ultra-fast")
        XCTAssertEqual(BuiltinSearchToolHub.tavilyDepthValue("garbage"), "basic")
    }

    // MARK: - Fixtures

    private func makeArgs(
        recencyDays: Int? = nil
    ) -> BuiltinSearchToolHub.ResolvedArguments {
        BuiltinSearchToolHub.ResolvedArguments(
            query: "swift",
            maxResults: 8,
            recencyDays: recencyDays,
            includeRawContent: false,
            fetchPageContent: false,
            includeDomains: [],
            excludeDomains: []
        )
    }

    private func makeSettings(
        tavilyCountry: String? = nil,
        tavilyAutoParameters: Bool = false,
        tavilySearchDepth: String? = nil,
        tavilyTopic: String? = nil
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .tavily,
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
            tavilySearchDepth: tavilySearchDepth,
            tavilyTopic: tavilyTopic,
            tavilyCountry: tavilyCountry,
            tavilyAutoParameters: tavilyAutoParameters,
            perplexityCountry: nil,
            perplexityLanguage: nil
        )
    }
}
