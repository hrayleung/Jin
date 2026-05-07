import Foundation

enum SearchRedirectQueryParameterSupport {
    static let targetURLKeys = ["url", "u", "target", "dest", "redirect", "adurl"]
    static let targetURLKeysIncludingLink = targetURLKeys + ["link"]
    static let searchHintKeys = ["q", "query", "search", "search_term"]

    static func firstDecodedURL(
        from queryItems: [URLQueryItem],
        matchingAnyOf keys: [String]
    ) -> URL? {
        for decodedValue in decodedQueryValues(from: queryItems, matchingAnyOf: keys) {
            guard let url = URL(string: decodedValue) else {
                continue
            }
            return url
        }

        return nil
    }

    static func firstDecodedNonEmptyValue(
        from queryItems: [URLQueryItem],
        matchingAnyOf keys: [String]
    ) -> String? {
        for decodedValue in decodedQueryValues(from: queryItems, matchingAnyOf: keys) {
            guard let nonEmptyValue = decodedValue.trimmedNonEmpty else {
                continue
            }
            return nonEmptyValue
        }

        return nil
    }

    private static func decodedQueryValues(
        from queryItems: [URLQueryItem],
        matchingAnyOf keys: [String]
    ) -> [String] {
        queryValues(from: queryItems, matchingAnyOf: keys)
            .map(decodedQueryValue)
    }

    private static func decodedQueryValue(_ rawValue: String) -> String {
        rawValue.removingPercentEncoding ?? rawValue
    }

    private static func queryValues(
        from queryItems: [URLQueryItem],
        matchingAnyOf keys: [String]
    ) -> [String] {
        keys.compactMap { key in
            queryItems.first {
                $0.name.caseInsensitiveCompare(key) == .orderedSame
            }?.value
        }
    }
}
