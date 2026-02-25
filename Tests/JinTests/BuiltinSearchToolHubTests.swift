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

    private func configurePluginDefaults(
        defaultProvider: SearchPluginProvider,
        exaKey: String = "",
        braveKey: String = "",
        jinaKey: String = "",
        firecrawlKey: String = ""
    ) {
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(defaultProvider.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set(exaKey, forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        defaults.set(braveKey, forKey: AppPreferenceKeys.pluginWebSearchBraveAPIKey)
        defaults.set(jinaKey, forKey: AppPreferenceKeys.pluginWebSearchJinaAPIKey)
        defaults.set(firecrawlKey, forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
    }
}
