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
        configurePluginDefaults(defaultProvider: .exa, exaKey: "exa-key")

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

    private func configurePluginDefaults(
        defaultProvider: SearchPluginProvider,
        exaKey: String = "",
        braveKey: String = "",
        jinaKey: String = "",
        firecrawlKey: String = "",
        perplexityKey: String = ""
    ) {
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(defaultProvider.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set(exaKey, forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        defaults.set(braveKey, forKey: AppPreferenceKeys.pluginWebSearchBraveAPIKey)
        defaults.set(jinaKey, forKey: AppPreferenceKeys.pluginWebSearchJinaAPIKey)
        defaults.set(firecrawlKey, forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        defaults.set(perplexityKey, forKey: AppPreferenceKeys.pluginWebSearchPerplexityAPIKey)
    }

    func testExaSearchTypeLegacyKeywordMapsToFast() {
        XCTAssertEqual(ExaSearchType.resolved(from: "keyword"), .fast)
        XCTAssertEqual(ExaSearchType.resolved(from: " auto "), .auto)
        XCTAssertNil(ExaSearchType.resolved(from: ""))
        XCTAssertNil(ExaSearchType.resolved(from: nil))
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
