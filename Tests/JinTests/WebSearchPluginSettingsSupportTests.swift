import XCTest
@testable import Jin

final class WebSearchPluginSettingsSupportTests: XCTestCase {
    func testProviderFallsBackToExaForUnknownRawValue() {
        XCTAssertEqual(WebSearchPluginSettingsSupport.provider(rawValue: "brave"), .brave)
        XCTAssertEqual(WebSearchPluginSettingsSupport.provider(rawValue: "unknown"), .exa)
        XCTAssertEqual(WebSearchPluginSettingsSupport.provider(rawValue: ""), .exa)
    }

    func testEffectiveMaxResultsKeepsDefaultAndClampsRange() {
        XCTAssertEqual(WebSearchPluginSettingsSupport.effectiveMaxResults(0), 8)
        XCTAssertEqual(WebSearchPluginSettingsSupport.effectiveMaxResults(-2), 1)
        XCTAssertEqual(WebSearchPluginSettingsSupport.effectiveMaxResults(12), 12)
        XCTAssertEqual(WebSearchPluginSettingsSupport.effectiveMaxResults(99), 50)
    }

    func testConfiguredCredentialTrimsWhitespace() {
        XCTAssertFalse(WebSearchPluginSettingsSupport.hasConfiguredCredential(""))
        XCTAssertFalse(WebSearchPluginSettingsSupport.hasConfiguredCredential(" \n\t "))
        XCTAssertTrue(WebSearchPluginSettingsSupport.hasConfiguredCredential(" key "))
        XCTAssertEqual(WebSearchPluginSettingsSupport.credentialStatusText(apiKey: ""), "Not configured")
        XCTAssertEqual(WebSearchPluginSettingsSupport.credentialStatusText(apiKey: " key "), "Configured")
    }

    func testConfiguredProvidersFollowProviderOrderAndSkipBlankKeys() {
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.configuredProviders(apiKeys: [
                .perplexity: "pplx",
                .exa: " ",
                .brave: "brave",
                .jina: "jina"
            ]),
            [.brave, .jina, .perplexity]
        )
    }

    func testConfiguredProviderPresentationSummaries() {
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.configuredCountText([.exa, .brave]),
            "2/6"
        )
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.configuredProviderNamesText([.exa, .brave]),
            "Exa · Brave Search"
        )
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.configuredProviderNamesText([]),
            ""
        )
    }

    func testInitialCredentialEditorProviderPrefersFirstConfiguredProvider() {
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.initialCredentialEditorProvider(
                configuredProviders: [.brave, .jina],
                defaultProvider: .exa
            ),
            .brave
        )
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.initialCredentialEditorProvider(
                configuredProviders: [],
                defaultProvider: .tavily
            ),
            .tavily
        )
    }

    func testRecencyChoicesMatchSettingsMenuOrder() {
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.recencyChoices.map(\.label),
            ["Any time", "Past day", "Past week", "Past month"]
        )
        XCTAssertEqual(
            WebSearchPluginSettingsSupport.recencyChoices.map(\.value),
            [0, 1, 7, 30]
        )
    }
}
