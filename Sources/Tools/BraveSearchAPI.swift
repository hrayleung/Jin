import Foundation

enum BraveSearchAPI {
    static let maxCount = 20
    static let maxOffset = 9
    /// LLM Context `count` / `maximum_number_of_urls` upper bound (docs: 1...50).
    static let llmContextMaxCount = 50

    static func makeWebSearchURL(
        query: String,
        count: Int,
        offset: Int? = nil,
        freshness: String? = nil,
        country: String? = nil,
        searchLanguage: String? = nil,
        uiLanguage: String? = nil,
        safesearch: String? = nil,
        extraSnippets: Bool = false,
        goggles: [String] = [],
        summary: Bool? = nil,
        enableRichCallback: Bool? = nil
    ) -> URL? {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count.clamped(to: 1...maxCount)))
        ]

        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset.clamped(to: 0...maxOffset))))
        }

        if let freshness = normalizedTrimmedString(freshness) {
            queryItems.append(URLQueryItem(name: "freshness", value: freshness))
        }

        if let country = normalizedTrimmedString(country) {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }

        if let searchLanguage = normalizedTrimmedString(searchLanguage) {
            queryItems.append(URLQueryItem(name: "search_lang", value: searchLanguage))
        }

        if let uiLanguage = normalizedTrimmedString(uiLanguage) {
            queryItems.append(URLQueryItem(name: "ui_lang", value: uiLanguage))
        }

        if let safesearch = normalizedTrimmedString(safesearch) {
            queryItems.append(URLQueryItem(name: "safesearch", value: safesearch))
        }

        if extraSnippets {
            queryItems.append(URLQueryItem(name: "extra_snippets", value: "true"))
        }

        for gogglesID in goggles.compactMap(normalizedTrimmedString) {
            queryItems.append(URLQueryItem(name: "goggles", value: gogglesID))
        }

        if summary == true {
            queryItems.append(URLQueryItem(name: "summary", value: "1"))
        }

        if enableRichCallback == true {
            queryItems.append(URLQueryItem(name: "enable_rich_callback", value: "1"))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    /// Builds a URL for Brave's AI-optimized LLM Context endpoint.
    /// Docs: `GET https://api.search.brave.com/res/v1/llm/context`
    static func makeLLMContextURL(
        query: String,
        count: Int,
        maximumNumberOfURLs: Int? = nil,
        freshness: String? = nil,
        country: String? = nil,
        searchLanguage: String? = nil,
        safesearch: String? = nil,
        enableSourceMetadata: Bool = true
    ) -> URL? {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/llm/context")

        let clampedCount = count.clamped(to: 1...llmContextMaxCount)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(clampedCount))
        ]

        let urlCap = (maximumNumberOfURLs ?? clampedCount).clamped(to: 1...llmContextMaxCount)
        queryItems.append(URLQueryItem(name: "maximum_number_of_urls", value: String(urlCap)))

        if let freshness = normalizedTrimmedString(freshness) {
            queryItems.append(URLQueryItem(name: "freshness", value: freshness))
        }

        if let country = normalizedTrimmedString(country) {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }

        if let searchLanguage = normalizedTrimmedString(searchLanguage) {
            queryItems.append(URLQueryItem(name: "search_lang", value: searchLanguage))
        }

        if let safesearch = normalizedTrimmedString(safesearch) {
            queryItems.append(URLQueryItem(name: "safesearch", value: safesearch))
        }

        if enableSourceMetadata {
            queryItems.append(URLQueryItem(name: "enable_source_metadata", value: "true"))
        }

        components?.queryItems = queryItems
        return components?.url
    }
}
