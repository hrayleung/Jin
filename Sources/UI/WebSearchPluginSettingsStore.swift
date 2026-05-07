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
    var perplexityAPIKey: String
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
        case .perplexity:
            return perplexityAPIKey
        }
    }

    func hasConfiguredCredential(for provider: SearchPluginProvider) -> Bool {
        apiKey(for: provider).trimmedNonEmpty != nil
    }
}

enum WebSearchPluginSettingsStore {
    static func load(defaults: UserDefaults = .standard) -> WebSearchPluginSettings {
        func trimmedPreference(_ key: String) -> String? {
            defaults.string(forKey: key)?.trimmedNonEmpty
        }

        let providerRaw = defaults.string(forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        let defaultProvider = SearchPluginProvider(rawValue: providerRaw ?? "") ?? .exa

        let maxResultsStored = defaults.integer(forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        let defaultMaxResults = (maxResultsStored == 0 ? 8 : maxResultsStored).clamped(to: 1...50)

        let recencyStored = defaults.integer(forKey: AppPreferenceKeys.pluginWebSearchDefaultRecencyDays)
        let defaultRecencyDays: Int?
        if recencyStored <= 0 {
            defaultRecencyDays = nil
        } else {
            defaultRecencyDays = recencyStored.clamped(to: 1...365)
        }

        let exaType = ExaSearchType.resolved(from: defaults.string(forKey: AppPreferenceKeys.pluginWebSearchExaSearchType))

        let braveCountry = trimmedPreference(AppPreferenceKeys.pluginWebSearchBraveCountry)
        let braveLanguage = trimmedPreference(AppPreferenceKeys.pluginWebSearchBraveLanguage)
        let braveSafesearch = trimmedPreference(AppPreferenceKeys.pluginWebSearchBraveSafesearch)

        let tavilySearchDepth = trimmedPreference(AppPreferenceKeys.pluginWebSearchTavilySearchDepth)
        let tavilyTopic = trimmedPreference(AppPreferenceKeys.pluginWebSearchTavilyTopic)

        return WebSearchPluginSettings(
            isEnabled: AppPreferences.isPluginEnabled("web_search_builtin", defaults: defaults),
            defaultProvider: defaultProvider,
            defaultMaxResults: defaultMaxResults,
            defaultRecencyDays: defaultRecencyDays,
            exaAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchExaAPIKey) ?? "",
            braveAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchBraveAPIKey) ?? "",
            jinaAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchJinaAPIKey) ?? "",
            firecrawlAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey) ?? "",
            exaSearchType: exaType,
            braveCountry: braveCountry,
            braveLanguage: braveLanguage,
            braveSafesearch: braveSafesearch,
            jinaReadPages: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchJinaReadPages) as? Bool ?? true,
            firecrawlExtractContent: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlExtractContent) as? Bool ?? true,
            tavilyAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchTavilyAPIKey) ?? "",
            perplexityAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchPerplexityAPIKey) ?? "",
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
}
