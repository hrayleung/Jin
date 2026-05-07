import Collections
import Foundation

extension CodexAppServerAdapter {
    nonisolated static func isLikelyWebSearchTool(named rawName: String) -> Bool {
        let normalized = rawName
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let canonical = normalized.replacingOccurrences(of: ".", with: "_")

        let knownNames: Set<String> = [
            "web_search",
            "websearch",
            "search_web",
            "browser.search",
            "browser_search",
        ]
        if knownNames.contains(normalized) || knownNames.contains(canonical) {
            return true
        }

        let tokens = Set(
            canonical
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if tokens.contains("websearch") {
            return true
        }
        if tokens.contains("browser") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("web") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("search") && tokens.contains("engine") {
            return true
        }
        return false
    }

    nonisolated static func preferredSnippetValue(from object: [String: JSONValue]) -> String? {
        let candidatePaths: [[String]] = [
            ["snippet"],
            ["summary"],
            ["description"],
            ["preview"],
            ["excerpt"],
            ["citedText"],
            ["cited_text"],
            ["quote"],
            ["abstract"],
        ]

        for path in candidatePaths {
            if let value = trimmedValue(object.string(at: path)) {
                return value
            }
        }
        return nil
    }

    nonisolated static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"https?://[^\s<>"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var resultsByKey: OrderedDictionary<String, String> = [:]
        for match in matches {
            let url = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard !url.isEmpty else { continue }
            let key = urlDeduplicationKey(for: url)
            guard resultsByKey[key] == nil else { continue }
            resultsByKey[key] = url
        }
        return Array(resultsByKey.values)
    }

    nonisolated static func urlDeduplicationKey(for rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else {
            return rawURL
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? rawURL
    }
}
