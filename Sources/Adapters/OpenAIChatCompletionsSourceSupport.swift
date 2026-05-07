import Collections
import Foundation

enum OpenAIChatCompletionsSourceSupport {
    static func sourcesMarkdown(
        citations: [String]?,
        searchResults: [OpenAIChatCompletionsSearchResult]?
    ) -> String? {
        if let searchResults {
            let searchResultLines = sourceLines(searchResults: searchResults)
            if !searchResultLines.isEmpty {
                return markdown(from: searchResultLines)
            }
        }

        let citationLines = sourceLines(citations: citations)
        guard !citationLines.isEmpty else { return nil }
        return markdown(from: citationLines)
    }

    private static func sourceLines(searchResults: [OpenAIChatCompletionsSearchResult]) -> [String] {
        var seenURLs = OrderedSet<String>()
        var lines: [String] = []
        lines.reserveCapacity(searchResults.count)

        for raw in searchResults {
            guard let url = normalizedTrimmedString(raw.url) else { continue }
            guard !seenURLs.contains(url) else { continue }
            seenURLs.append(url)

            let number = seenURLs.count
            let title = normalizedTrimmedString(raw.title) ?? url
            let titleEscaped = escapeMarkdownLinkText(title)
            var line = "\(number). [\(titleEscaped)](<\(url)>)"

            if let snippet = normalizedTrimmedString(raw.snippet) {
                let oneLine = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                line += " — \(oneLine)"
            }

            lines.append(line)
        }

        return lines
    }

    private static func sourceLines(citations: [String]?) -> [String] {
        guard let citations else { return [] }

        var unique = OrderedSet<String>()
        unique.reserveCapacity(citations.count)

        for raw in citations {
            guard let trimmed = normalizedTrimmedString(raw) else { continue }
            if !unique.contains(trimmed) {
                unique.append(trimmed)
            }
        }

        return unique.elements.enumerated().map { index, citation in
            let number = index + 1
            if citation.lowercased().hasPrefix("http") {
                return "\(number). <\(citation)>"
            }
            return "\(number). \(citation)"
        }
    }

    private static func markdown(from sourceLines: [String]) -> String {
        (["\n\n---\n\n### Sources"] + sourceLines).joined(separator: "\n")
    }

    private static func escapeMarkdownLinkText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
