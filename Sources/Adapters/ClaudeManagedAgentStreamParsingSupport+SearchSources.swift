import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func extractSearchSources(from object: [String: JSONValue]) -> [[String: Any]] {
        var accumulator = SearchSourceAccumulator()

        func visit(_ value: JSONValue) {
            switch value {
            case .array(let array):
                array.forEach(visit)

            case .object(let candidate):
                appendSearchSourceCandidate(candidate, to: &accumulator)
                candidate.values.forEach(visit)

            default:
                break
            }
        }

        visit(.object(object))

        if accumulator.isEmpty {
            let allText = collectTextFragments(from: .object(object)).joined(separator: "\n")
            for url in extractURLs(from: allText) {
                accumulator.append(url: url, title: nil, snippet: nil)
            }
        }

        return accumulator.sources
    }

    private static func appendSearchSourceCandidate(
        _ candidate: [String: JSONValue],
        to accumulator: inout SearchSourceAccumulator
    ) {
        let nestedSource = candidate.object(at: ["source"])
        accumulator.append(
            url: searchSourceURL(from: candidate, nestedSource: nestedSource),
            title: searchSourceTitle(from: candidate, nestedSource: nestedSource),
            snippet: searchSourceSnippet(from: candidate, nestedSource: nestedSource)
        )
    }

    private static func searchSourceURL(
        from candidate: [String: JSONValue],
        nestedSource: [String: JSONValue]?
    ) -> String? {
        normalizedTrimmedString(candidate.string(at: ["url"]))
            ?? normalizedTrimmedString(candidate.string(at: ["source"])).flatMap { looksLikeURL($0) ? $0 : nil }
            ?? nestedSource?.string(at: ["url"])
    }

    private static func searchSourceTitle(
        from candidate: [String: JSONValue],
        nestedSource: [String: JSONValue]?
    ) -> String? {
        candidate.string(at: ["title"])
            ?? candidate.string(at: ["name"])
            ?? nestedSource?.string(at: ["title"])
            ?? nestedSource?.string(at: ["name"])
    }

    private static func searchSourceSnippet(
        from candidate: [String: JSONValue],
        nestedSource: [String: JSONValue]?
    ) -> String? {
        preferredSearchSnippet(from: candidate)
            ?? nestedSource.flatMap(preferredSearchSnippet(from:))
    }

    static func searchActivityArguments(sources: [[String: Any]]) -> [String: AnyCodable] {
        guard !sources.isEmpty else { return [:] }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(sources)
        ]

        if let firstURL = sources.first?["url"] as? String {
            arguments["url"] = AnyCodable(firstURL)
        }
        if let firstTitle = sources.first?["title"] as? String {
            arguments["title"] = AnyCodable(firstTitle)
        }

        return arguments
    }

    static func preferredSearchSnippet(from object: [String: JSONValue]) -> String? {
        let candidatePaths: [[String]] = [
            ["snippet"],
            ["summary"],
            ["description"],
            ["preview"],
            ["excerpt"],
            ["cited_text"],
            ["citedText"],
            ["quote"],
            ["abstract"],
            ["text"],
        ]

        for path in candidatePaths {
            if let snippet = normalizedTrimmedString(object.string(at: path)) {
                return snippet
            }
        }

        return nil
    }

    static func collectTextFragments(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]
        case .array(let array):
            return array.flatMap(collectTextFragments(from:))
        case .object(let object):
            return object.values.flatMap(collectTextFragments(from:))
        default:
            return []
        }
    }

    static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"https?://[^\s<>"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var results: [String] = []
        var seenKeys: Set<String> = []
        for match in matches {
            let url = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard !url.isEmpty else { continue }
            let dedupeKey = urlDeduplicationKey(for: url)
            guard !seenKeys.contains(dedupeKey) else { continue }
            seenKeys.insert(dedupeKey)
            results.append(url)
        }

        return results
    }

    static func urlDeduplicationKey(for rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else {
            return rawURL.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return (components.string ?? rawURL).lowercased()
    }

    static func looksLikeURL(_ rawValue: String) -> Bool {
        let lowercased = rawValue.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }
}

private struct SearchSourceAccumulator {
    private var orderedKeys: [String] = []
    private var sourcesByKey: [String: [String: Any]] = [:]

    var isEmpty: Bool {
        sourcesByKey.isEmpty
    }

    var sources: [[String: Any]] {
        orderedKeys.compactMap { sourcesByKey[$0] }
    }

    mutating func append(url rawURL: String?, title: String?, snippet: String?) {
        guard let normalizedURL = normalizedTrimmedString(rawURL) else { return }
        let dedupeKey = ClaudeManagedAgentStreamParsingSupport.urlDeduplicationKey(for: normalizedURL)

        var source = sourcesByKey[dedupeKey] ?? ["url": normalizedURL]
        if source["title"] == nil, let title = normalizedTrimmedString(title) {
            source["title"] = title
        }
        if source["snippet"] == nil, let snippet = normalizedTrimmedString(snippet) {
            source["snippet"] = snippet
        }
        if sourcesByKey[dedupeKey] == nil {
            orderedKeys.append(dedupeKey)
        }
        sourcesByKey[dedupeKey] = source
    }
}
