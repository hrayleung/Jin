import Foundation

enum GoogleGroundingSearchSuggestionParser {
    struct Suggestion: Sendable {
        let query: String?
        let url: String
    }

    static func parse(sdkBlob: String?) -> [Suggestion] {
        guard let blob = sdkBlob?.trimmingCharacters(in: .whitespacesAndNewlines), !blob.isEmpty else {
            return []
        }
        guard let data = decodeBase64Payload(blob) else {
            return []
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var suggestions: [Suggestion] = []
        var seenURLKeys: Set<String> = []

        func normalizedURL(from raw: Any?) -> String? {
            guard let raw = raw as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return url.absoluteString
        }

        func normalizedQuery(from raw: Any?) -> String? {
            guard let raw = raw as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func appendSuggestion(urlRaw: Any?, queryRaw: Any?) {
            guard let url = normalizedURL(from: urlRaw) else { return }
            let dedupeKey = url.lowercased()
            guard seenURLKeys.insert(dedupeKey).inserted else { return }
            suggestions.append(Suggestion(query: normalizedQuery(from: queryRaw), url: url))
        }

        func walk(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                let urlRaw = dictionary["url"] ?? dictionary["uri"] ?? dictionary["link"]
                let queryRaw = dictionary["query"] ?? dictionary["q"] ?? dictionary["searchQuery"] ?? dictionary["search_term"]
                appendSuggestion(urlRaw: urlRaw, queryRaw: queryRaw)

                for value in dictionary.values {
                    walk(value)
                }
                return
            }

            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(root)
        return suggestions
    }

    private static func decodeBase64Payload(_ raw: String) -> Data? {
        if let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters), !data.isEmpty {
            return data
        }

        let urlSafe = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = urlSafe.count % 4
        let padded: String
        if remainder == 0 {
            padded = urlSafe
        } else {
            padded = urlSafe + String(repeating: "=", count: 4 - remainder)
        }

        if let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters), !data.isEmpty {
            return data
        }

        return nil
    }
}
