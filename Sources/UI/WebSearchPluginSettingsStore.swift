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
    var exaCategory: String?
    var exaUserLocation: String?
    var exaModeration: Bool

    var braveCountry: String?
    var braveLanguage: String?
    var braveSafesearch: String?

    var jinaReadPages: Bool
    var jinaCountry: String?
    var jinaLocale: String?

    var firecrawlExtractContent: Bool
    var firecrawlCountry: String?
    var firecrawlLanguage: String?
    var firecrawlSources: [FirecrawlSourceKind]

    var tavilyAPIKey: String
    var perplexityAPIKey: String
    var tavilySearchDepth: String?  // "basic" | "fast" | "advanced" | "ultra-fast"
    var tavilyTopic: String?        // "general" | "news" | "finance"
    var tavilyCountry: String?
    var tavilyAutoParameters: Bool

    var perplexityCountry: String?
    var perplexityLanguage: String?

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
            exaCategory: trimmedPreference(AppPreferenceKeys.pluginWebSearchExaCategory),
            exaUserLocation: trimmedPreference(AppPreferenceKeys.pluginWebSearchExaUserLocation),
            exaModeration: defaults.bool(forKey: AppPreferenceKeys.pluginWebSearchExaModeration),
            braveCountry: braveCountry,
            braveLanguage: braveLanguage,
            braveSafesearch: braveSafesearch,
            jinaReadPages: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchJinaReadPages) as? Bool ?? true,
            jinaCountry: trimmedPreference(AppPreferenceKeys.pluginWebSearchJinaCountry),
            jinaLocale: trimmedPreference(AppPreferenceKeys.pluginWebSearchJinaLocale),
            firecrawlExtractContent: defaults.object(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlExtractContent) as? Bool ?? true,
            firecrawlCountry: trimmedPreference(AppPreferenceKeys.pluginWebSearchFirecrawlCountry),
            firecrawlLanguage: trimmedPreference(AppPreferenceKeys.pluginWebSearchFirecrawlLanguage),
            firecrawlSources: decodeFirecrawlSources(defaults.string(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlSources)),
            tavilyAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchTavilyAPIKey) ?? "",
            perplexityAPIKey: trimmedPreference(AppPreferenceKeys.pluginWebSearchPerplexityAPIKey) ?? "",
            tavilySearchDepth: tavilySearchDepth,
            tavilyTopic: tavilyTopic,
            tavilyCountry: trimmedPreference(AppPreferenceKeys.pluginWebSearchTavilyCountry),
            tavilyAutoParameters: defaults.bool(forKey: AppPreferenceKeys.pluginWebSearchTavilyAutoParameters),
            perplexityCountry: trimmedPreference(AppPreferenceKeys.pluginWebSearchPerplexityCountry),
            perplexityLanguage: trimmedPreference(AppPreferenceKeys.pluginWebSearchPerplexityLanguage)
        )
    }

    static func hasAnyConfiguredProvider(defaults: UserDefaults = .standard) -> Bool {
        let settings = load(defaults: defaults)
        return SearchPluginProvider.allCases.contains { settings.hasConfiguredCredential(for: $0) }
    }

    static func hasConfiguredProvider(_ provider: SearchPluginProvider, defaults: UserDefaults = .standard) -> Bool {
        load(defaults: defaults).hasConfiguredCredential(for: provider)
    }

    static func encodeFirecrawlSources(_ kinds: [FirecrawlSourceKind]) -> String {
        guard !kinds.isEmpty else { return "" }
        let raw = kinds.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static func firecrawlSourceSelection(from stored: String?) -> [FirecrawlSourceKind] {
        let decoded = decodeFirecrawlSources(stored)
        return decoded.isEmpty ? [.web] : decoded
    }

    private static func decodeFirecrawlSources(_ stored: String?) -> [FirecrawlSourceKind] {
        guard let stored = stored?.trimmedNonEmpty,
              let data = stored.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return raw.compactMap(FirecrawlSourceKind.init(rawValue:))
    }
}
