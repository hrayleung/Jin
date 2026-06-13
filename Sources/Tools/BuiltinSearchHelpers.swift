import Collections
import Foundation

// MARK: - JSON Parsing, Date Formatting, Provider-Specific Converters

extension BuiltinSearchToolHub {
    func parseJSON(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "Expected JSON object response.")
        }
        return object
    }

    func parseArray(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    func stringValues(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.compactMap { normalizedTrimmedString($0) }
        }
        if let values = value as? [Any] {
            return values.compactMap { item in
                if let value = item as? String {
                    return normalizedTrimmedString(value)
                }
                if let value = item as? [String: Any],
                   let text = firstString(in: value, keys: ["text", "message", "detail"]) {
                    return text
                }
                return nil
            }
        }
        return []
    }

    nonisolated func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        Self.firstString(in: dictionary, keys: keys)
    }

    nonisolated static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               let trimmed = value.trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
    }

    func firstInt(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? Double {
                return Int(value.rounded())
            }
            if let value = dictionary[key] as? String,
               let intValue = Int(value.trimmed) {
                return intValue
            }
        }
        return nil
    }

    func firstBool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? String {
                switch value.trimmedLowercased {
                case "true", "1", "yes", "on":
                    return true
                case "false", "0", "no", "off":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    func firecrawlErrorMessage(from json: [String: Any]) -> String {
        if let errors = firstString(in: json, keys: ["error", "message", "status"]) {
            return errors
        }

        let flattenedErrors = stringValues(json["errors"])
        if let first = flattenedErrors.first {
            return first
        }

        if let details = firstString(in: json, keys: ["details"]),
           !details.isEmpty {
            return details
        }

        return "Unknown Firecrawl error."
    }

    func highlights(from value: Any?) -> [String: Any]? {
        if let values = value as? [String] {
            return values.isEmpty ? nil : ["text": values[0]]
        }
        if let value = value as? [[String: Any]], let first = value.first {
            return first
        }
        return value as? [String: Any]
    }

    func firstStringArray(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = dictionary[key] as? [String] {
                return value.compactMap { normalizedTrimmedString($0) }
            }
            if let value = dictionary[key] as? [Any] {
                return value.compactMap { item in
                    normalizedTrimmedString(item as? String)
                }
            }
        }
        return []
    }

    static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Formats `date` using the given `dateFormat` in UTC/POSIX locale.
    /// Shared by any provider that needs a simple date-only string (e.g. `yyyy-MM-dd`).
    nonisolated static func utcDateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Returns a Gregorian calendar whose time zone is UTC. Shared by providers that
    /// need date arithmetic (e.g. adding days) before formatting.
    nonisolated static func utcGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    func prettyJSONString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Augments a Firecrawl query with Google-style `site:` / `-site:` operators because the v2
    /// search endpoint does not accept first-class include/exclude domain arrays.
    /// Caps each list at 10 entries to keep the URL/query sane.
    static func firecrawlAugmentedQuery(
        _ query: String,
        includeDomains: [String],
        excludeDomains: [String]
    ) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let includes = includeDomains.compactMap { $0.trimmedNonEmpty }.prefix(10)
        let excludes = excludeDomains.compactMap { $0.trimmedNonEmpty }.prefix(10)

        var pieces: [String] = trimmed.isEmpty ? [] : [trimmed]

        if !includes.isEmpty {
            let operators = includes.map { "site:\($0)" }
            pieces.append(operators.count == 1 ? operators[0] : "(\(operators.joined(separator: " OR ")))")
        }

        for domain in excludes {
            pieces.append("-site:\(domain)")
        }

        return pieces.joined(separator: " ")
    }

    func urlHost(_ urlString: String) -> String? {
        URL(string: urlString)?.host
    }

    /// Builds a `SearchCitationRow` from a raw JSON dictionary using the supplied key lists.
    /// Returns `nil` if none of `urlKeys` resolves to a non-empty string.
    /// Applies the standard 500-character snippet cap and falls back to `host ?? url` for the title.
    /// Use this for providers whose row shape is: plain url guard → title-with-host-fallback →
    /// 500-capped snippet → publishedAt → source=host.
    /// Providers with custom snippet logic (Exa's highlight chain, Brave's multi-field join)
    /// or a nonisolated-static context (Firecrawl) must keep their own row-building code.
    func citationRow(
        from item: [String: Any],
        urlKeys: [String],
        snippetKeys: [String],
        publishedAtKeys: [String]
    ) -> SearchCitationRow? {
        guard let url = firstString(in: item, keys: urlKeys) else { return nil }
        let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
        let snippet = firstString(in: item, keys: snippetKeys).map { String($0.prefix(500)) }
        let publishedAt = firstString(in: item, keys: publishedAtKeys)
        return SearchCitationRow(title: title, url: url, snippet: snippet, publishedAt: publishedAt, source: urlHost(url))
    }

    func braveSnippet(from item: [String: Any], includeExtraSnippets: Bool) -> String? {
        var parts = OrderedSet<String>()

        for value in [
            firstString(in: item, keys: ["description"]),
            firstString(in: item, keys: ["snippet"])
        ].compactMap({ $0 }) {
            parts.append(value)
        }

        if includeExtraSnippets {
            let extras = firstStringArray(in: item, keys: ["extra_snippets"])
            for extra in extras {
                parts.append(extra)
            }
        }

        guard let joined = parts.elements.joined(separator: "\n").trimmedNonEmpty else { return nil }
        return String(joined.prefix(500))
    }
}
