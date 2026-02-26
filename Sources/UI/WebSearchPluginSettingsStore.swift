import Foundation

struct WebSearchPluginSettings: Sendable {
    var isEnabled: Bool
    var defaultProvider: SearchPluginProvider

    var defaultMaxResults: Int
    var defaultRecencyDays: Int?

    var exaAPIKey: String
    var braveAPIKey: String
    var jinaAPIKey: String
    var firecrawlAPIKey: String

    var exaSearchType: ExaSearchType?

    var braveCountry: String?
    var braveLanguage: String?
    var braveSafesearch: String?

    var jinaReadPages: Bool
    var firecrawlExtractContent: Bool

    var tavilyAPIKey: String
    var tavilySearchDepth: String?  // "basic" | "fast" | "advanced" | "ultra-fast"
    var tavilyTopic: String?        // "general" | "news" | "finance"

    func apiKey(for provider: SearchPluginProvider) -> String {
        switch provider {
        case .exa:
            return exaAPIKey
        case .brave:
            return braveAPIKey
        case .jina:
            return jinaAPIKey
        case .firecrawl:
            return firecrawlAPIKey
        case .tavily:
            return tavilyAPIKey
        }
    }

    func hasConfiguredCredential(for provider: SearchPluginProvider) -> Bool {
        !apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum WebSearchPluginSettingsStore {
    static func load(defaults: UserDefaults = .standard) -> WebSearchPluginSettings {
        let providerRaw = defaults.string(forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        let defaultProvider = SearchPluginProvider(rawValue: providerRaw ?? "") ?? .exa

        let maxResultsStored = defaults.integer(forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        let defaultMaxResults = clamp(maxResultsStored == 0 ? 8 : maxResultsStored, min: 1, max: 50)

        let recencyStored = defaults.integer(forKey: AppPreferenceKeys.pluginWebSearchDefaultRecencyDays)
        let defaultRecencyDays: Int?
        if recencyStored <= 0 {
            defaultRecencyDays = nil
        } else {
            defaultRecencyDays = clamp(recencyStored, min: 1, max: 365)
        }

        let exaType = ExaSearchType.resolved(from: defaults.string(forKey: AppPreferenceKeys.pluginWebSearchExaSearchType))

        let braveCountry = trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchBraveCountry))
        let braveLanguage = trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchBraveLanguage))
        let braveSafesearch = trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchBraveSafesearch))

        let tavilySearchDepth = trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchTavilySearchDepth))
        let tavilyTopic = trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchTavilyTopic))

        return WebSearchPluginSettings(
            isEnabled: AppPreferences.isPluginEnabled("web_search_builtin", defaults: defaults),
            defaultProvider: defaultProvider,
            defaultMaxResults: defaultMaxResults,
            defaultRecencyDays: defaultRecencyDays,
            exaAPIKey: trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)) ?? "",
            braveAPIKey: trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchBraveAPIKey)) ?? "",
            jinaAPIKey: trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchJinaAPIKey)) ?? "",
            firecrawlAPIKey: trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)) ?? "",
            exaSearchType: exaType,
            braveCountry: braveCountry,
            braveLanguage: braveLanguage,
            braveSafesearch: braveSafesearch,
            jinaReadPages: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchJinaReadPages) as? Bool ?? true,
            firecrawlExtractContent: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlExtractContent) as? Bool ?? true,
            tavilyAPIKey: trimmed(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchTavilyAPIKey)) ?? "",
            tavilySearchDepth: tavilySearchDepth,
            tavilyTopic: tavilyTopic
        )
    }

    static func hasAnyConfiguredProvider(defaults: UserDefaults = .standard) -> Bool {
        let settings = load(defaults: defaults)
        return SearchPluginProvider.allCases.contains { settings.hasConfiguredCredential(for: $0) }
    }

    static func hasConfiguredProvider(_ provider: SearchPluginProvider, defaults: UserDefaults = .standard) -> Bool {
        load(defaults: defaults).hasConfiguredCredential(for: provider)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}
