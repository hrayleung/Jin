import Foundation

enum WebSearchPluginSettingsSupport {
    struct RecencyChoice: Hashable, Identifiable {
        let label: String
        let value: Int

        var id: Int { value }
    }

    static let recencyChoices: [RecencyChoice] = [
        RecencyChoice(label: "Any time", value: 0),
        RecencyChoice(label: "Past day", value: 1),
        RecencyChoice(label: "Past week", value: 7),
        RecencyChoice(label: "Past month", value: 30)
    ]

    static func provider(rawValue: String) -> SearchPluginProvider {
        SearchPluginProvider(rawValue: rawValue) ?? .exa
    }

    static func effectiveMaxResults(_ storedValue: Int) -> Int {
        (storedValue == 0 ? 8 : storedValue).clamped(to: 1...50)
    }

    static func hasConfiguredCredential(_ apiKey: String) -> Bool {
        apiKey.trimmedNonEmpty != nil
    }

    static func credentialStatusText(apiKey: String) -> String {
        hasConfiguredCredential(apiKey) ? "Configured" : "Not configured"
    }

    static func configuredProviders(apiKeys: [SearchPluginProvider: String]) -> [SearchPluginProvider] {
        SearchPluginProvider.allCases.filter { provider in
            hasConfiguredCredential(apiKeys[provider] ?? "")
        }
    }

    static func configuredCountText(_ providers: [SearchPluginProvider]) -> String {
        "\(providers.count)/\(SearchPluginProvider.allCases.count)"
    }

    static func configuredProviderNamesText(_ providers: [SearchPluginProvider]) -> String {
        providers.map(\.displayName).joined(separator: " · ")
    }

    static func initialCredentialEditorProvider(
        configuredProviders: [SearchPluginProvider],
        defaultProvider: SearchPluginProvider
    ) -> SearchPluginProvider {
        configuredProviders.first ?? defaultProvider
    }
}
