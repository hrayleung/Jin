import XCTest
@testable import Jin

final class BuiltinSearchToolHubTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BuiltinSearchToolHubTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testToolDefinitionsRequireWebSearchEnabled() async {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "exa-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: false),
            searchPlugin: SearchPluginControls(provider: .exa)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertFalse(routes.contains(functionName: "builtin_search__web_lookup"))
    }

    func testToolDefinitionsExposeSingleBuiltinToolWhenConfigured() async throws {
        configurePluginDefaults(defaultProvider: .exa, exaKey: " \n exa-key \t ")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .exa)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(definitions.count, 1)
        let tool = try XCTUnwrap(definitions.first)
        if case .builtin = tool.source {
            // expected
        } else {
            XCTFail("Expected builtin tool source.")
        }
        XCTAssertTrue(routes.contains(functionName: tool.name))
        XCTAssertEqual(routes.provider(for: tool.name), .exa)
    }

    func testBuiltinSearchHelperParsersTrimStringsAndCoerceScalars() async {
        let hub = BuiltinSearchToolHub.shared
        let dictionary: [String: Any] = [
            "text": " \n Swift concurrency \t ",
            "count": " 12 ",
            "flag": " YES "
        ]

        let text = hub.firstString(in: dictionary, keys: ["text"])
        let count = await hub.firstInt(in: dictionary, keys: ["count"])
        let flag = await hub.firstBool(in: dictionary, keys: ["flag"])

        XCTAssertEqual(text, "Swift concurrency")
        XCTAssertEqual(count, 12)
        XCTAssertEqual(flag, true)
    }

    func testBuiltinSearchHelperParsersSkipBlankStrings() async {
        let hub = BuiltinSearchToolHub.shared
        let dictionary: [String: Any] = [
            "blank": " \n\t ",
            "fallback": " value "
        ]

        let value = hub.firstString(in: dictionary, keys: ["blank", "fallback"])
        XCTAssertEqual(value, "value")
    }

    func testToolDefinitionsDoNotFallbackWhenExplicitProviderMissingKey() async {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "", braveKey: "brave-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .exa)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertFalse(routes.contains(functionName: BuiltinSearchToolHub.functionName))
    }

    func testToolDefinitionsFallbackToConfiguredProviderWhenNoExplicitProvider() async throws {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "", braveKey: "brave-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: nil
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(definitions.count, 1)
        let tool = try XCTUnwrap(definitions.first)
        XCTAssertEqual(routes.provider(for: tool.name), .brave)
    }

    func testToolDefinitionsFallbackToTinyFishWhenOnlyTinyFishIsConfigured() async throws {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "", tinyfishKey: "tf-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: nil
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(definitions.count, 1)
        let tool = try XCTUnwrap(definitions.first)
        XCTAssertEqual(routes.provider(for: tool.name), .tinyfish)
    }

    func testToolDefinitionsFallbackToParallelWhenOnlyParallelIsConfigured() async throws {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "", parallelKey: "par-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: nil
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(definitions.count, 1)
        let tool = try XCTUnwrap(definitions.first)
        XCTAssertEqual(routes.provider(for: tool.name), .parallel)
    }

    func testParallelSearchReturnsEmptyResultWhenMaxResultsIsZero() async throws {
        configurePluginDefaults(defaultProvider: .parallel, parallelKey: "par-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .parallel, maxResults: 0)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        let tool = try XCTUnwrap(definitions.first)
        let result = try await BuiltinSearchToolHub.shared.executeTool(
            functionName: tool.name,
            arguments: [
                "query": AnyCodable("swift")
            ],
            routes: routes
        )

        XCTAssertFalse(result.isError)
        let data = Data(result.text.utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, SearchPluginProvider.parallel.rawValue)
        XCTAssertEqual(json["resultCount"] as? Int, 0)
        let rows = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertTrue(rows.isEmpty)
    }

    func testToolDefinitionsFallbackToPerplexityWhenOnlyPerplexityIsConfigured() async throws {
        configurePluginDefaults(defaultProvider: .exa, exaKey: "", perplexityKey: "pplx-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: nil
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(definitions.count, 1)
        let tool = try XCTUnwrap(definitions.first)
        XCTAssertEqual(routes.provider(for: tool.name), .perplexity)
    }

    func testPerplexitySearchReturnsEmptyResultWhenMaxResultsIsZero() async throws {
        configurePluginDefaults(defaultProvider: .perplexity, perplexityKey: "pplx-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .perplexity, maxResults: 0)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        let tool = try XCTUnwrap(definitions.first)
        let result = try await BuiltinSearchToolHub.shared.executeTool(
            functionName: tool.name,
            arguments: [
                "query": AnyCodable("swift")
            ],
            routes: routes
        )

        XCTAssertFalse(result.isError)
        let data = Data(result.text.utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, SearchPluginProvider.perplexity.rawValue)
        XCTAssertEqual(json["resultCount"] as? Int, 0)
        let rows = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertTrue(rows.isEmpty)
    }

    func testTinyFishSearchReturnsEmptyResultWhenMaxResultsIsZero() async throws {
        configurePluginDefaults(defaultProvider: .tinyfish, tinyfishKey: "tf-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .tinyfish, maxResults: 0)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        let tool = try XCTUnwrap(definitions.first)
        let result = try await BuiltinSearchToolHub.shared.executeTool(
            functionName: tool.name,
            arguments: [
                "query": AnyCodable("swift")
            ],
            routes: routes
        )

        XCTAssertFalse(result.isError)
        let data = Data(result.text.utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, SearchPluginProvider.tinyfish.rawValue)
        XCTAssertEqual(json["resultCount"] as? Int, 0)
        let rows = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertTrue(rows.isEmpty)
    }

    func testJinaSearchReturnsEmptyResultWhenMaxResultsIsZero() async throws {
        configurePluginDefaults(defaultProvider: .jina, jinaKey: "jina-key")

        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(provider: .jina, maxResults: 0)
        )

        let (definitions, routes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: controls,
            useBuiltinSearch: true,
            defaults: defaults
        )

        let tool = try XCTUnwrap(definitions.first)
        let result = try await BuiltinSearchToolHub.shared.executeTool(
            functionName: tool.name,
            arguments: [
                "query": AnyCodable("swift")
            ],
            routes: routes
        )

        XCTAssertFalse(result.isError)
        let data = Data(result.text.utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, SearchPluginProvider.jina.rawValue)
        XCTAssertEqual(json["resultCount"] as? Int, 0)
        let rows = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertTrue(rows.isEmpty)
    }

    private func configurePluginDefaults(
        defaultProvider: SearchPluginProvider,
        exaKey: String = "",
        braveKey: String = "",
        jinaKey: String = "",
        firecrawlKey: String = "",
        perplexityKey: String = "",
        tinyfishKey: String = "",
        parallelKey: String = ""
    ) {
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(defaultProvider.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set(exaKey, forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        defaults.set(braveKey, forKey: AppPreferenceKeys.pluginWebSearchBraveAPIKey)
        defaults.set(jinaKey, forKey: AppPreferenceKeys.pluginWebSearchJinaAPIKey)
        defaults.set(firecrawlKey, forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        defaults.set(perplexityKey, forKey: AppPreferenceKeys.pluginWebSearchPerplexityAPIKey)
        defaults.set(tinyfishKey, forKey: AppPreferenceKeys.pluginWebSearchTinyFishAPIKey)
        defaults.set(parallelKey, forKey: AppPreferenceKeys.pluginWebSearchParallelAPIKey)
    }

    func testExaSearchTypeLegacyKeywordMapsToFast() {
        XCTAssertEqual(ExaSearchType.resolved(from: "keyword"), .fast)
        XCTAssertEqual(ExaSearchType.resolved(from: " auto "), .auto)
        XCTAssertNil(ExaSearchType.resolved(from: ""))
        XCTAssertNil(ExaSearchType.resolved(from: nil))
    }

    func testExaSearchTypeLegacyNeuralMapsToAutoAndIsNotPublic() {
        XCTAssertEqual(ExaSearchType.resolved(from: "neural"), .auto)
        XCTAssertEqual(ExaSearchType.neural.wireValue, "auto")
        XCTAssertFalse(ExaSearchType.publicCases.contains(.neural))
    }

    func testExaCategoryLegacyPublicationMapsToResearchPaper() {
        XCTAssertEqual(ExaCategory.resolved(from: "research paper"), .researchPaper)
        XCTAssertEqual(ExaCategory.resolved(from: "research_paper"), .researchPaper)
        XCTAssertEqual(ExaCategory.resolved(from: "publication"), .researchPaper)
        XCTAssertEqual(ExaCategory.publication.rawValue, "publication")
        XCTAssertEqual(ExaCategory.publication.wireValue, "research paper")
        XCTAssertFalse(ExaCategory.publicCases.contains(.publication))
    }

    func testExaSearchTypeIncludesNewDeepVariants() {
        XCTAssertEqual(ExaSearchType.resolved(from: "deep-lite"), .deepLite)
        XCTAssertEqual(ExaSearchType.resolved(from: "deep-reasoning"), .deepReasoning)
        XCTAssertEqual(ExaSearchType.resolved(from: "deep"), .deep)
        XCTAssertTrue(ExaSearchType.publicCases.contains(.deepLite))
        XCTAssertTrue(ExaSearchType.publicCases.contains(.deepReasoning))
        XCTAssertTrue(ExaSearchType.publicCases.contains(.instant))
    }

    func testWebSearchPluginSettingsLoadMapsLegacyExaType() {
        defaults.set("keyword", forKey: AppPreferenceKeys.pluginWebSearchExaSearchType)
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.exaSearchType, .fast)
    }

    func testWebSearchPluginSettingsLoadPerplexityKey() {
        defaults.set("  pplx-key  ", forKey: AppPreferenceKeys.pluginWebSearchPerplexityAPIKey)
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.apiKey(for: .perplexity), "pplx-key")
    }
}
