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

    func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
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
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
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
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
        if let errors = firstString(in: json, keys: ["error", "message", "status"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !errors.isEmpty {
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

    func prettyJSONString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func braveFreshnessValue(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "pd"
        case ...7:
            return "pw"
        case ...31:
            return "pm"
        default:
            return "py"
        }
    }

    func tavilyTimeRange(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "day"
        case ...7:
            return "week"
        case ...31:
            return "month"
        default:
            return "year"
        }
    }

    func perplexityRecencyFilter(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "day"
        case ...7:
            return "week"
        case ...31:
            return "month"
        default:
            return "year"
        }
    }

    func perplexitySearchDomainFilter(includeDomains: [String], excludeDomains: [String]) -> [String] {
        let include = includeDomains.compactMap(normalizedTrimmedString)
        if !include.isEmpty {
            // Perplexity Search API allows either include-only or exclude-only filters.
            return Array(include.prefix(20))
        }

        let exclude = excludeDomains.compactMap(normalizedTrimmedString).map { "-\($0)" }
        return Array(exclude.prefix(20))
    }

    var tavilyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    func tavilySearchDepthValue(_ value: String?) -> String {
        guard let depth = normalizedTrimmedString(value)?.lowercased() else {
            return "basic"
        }
        let normalized = depth.replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "basic", "fast", "advanced", "ultra_fast":
            return normalized == "ultra_fast" ? "ultra-fast" : normalized
        default:
            return "basic"
        }
    }

    func tavilyTopicValue(_ value: String?) -> String {
        guard let topic = normalizedTrimmedString(value)?.lowercased() else { return "general" }
        switch topic {
        case "general", "news", "finance":
            return topic
        default:
            return "general"
        }
    }

    func firecrawlRecencyValue(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "qdr:d"
        case ...7:
            return "qdr:w"
        case ...31:
            return "qdr:m"
        default:
            return "qdr:y"
        }
    }

    func urlHost(_ urlString: String) -> String? {
        URL(string: urlString)?.host
    }

    func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
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

        let joined = parts.elements
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(500))
    }
}
