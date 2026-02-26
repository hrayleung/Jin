import Foundation

enum BraveSearchAPI {
    static let maxCount = 20
    static let maxOffset = 9

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
            URLQueryItem(name: "count", value: String(clamp(count, min: 1, max: maxCount)))
        ]

        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(clamp(offset, min: 0, max: maxOffset))))
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

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

