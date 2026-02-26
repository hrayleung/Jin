import Foundation

enum MistralOCRMarkdown {
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)]+)\\)")
    private static let tableRegex = try! NSRegularExpression(pattern: "\\[(tbl-[^\\]]+)\\]\\(([^)]+)\\)")

    static func referencedImageIDs(in markdown: String) -> [String] {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        return imageRegex
            .matches(in: markdown, range: range)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = ns.substring(with: match.range(at: 1))
                let normalized = normalizedResourceID(from: raw)
                return normalized.isEmpty ? nil : normalized
            }
    }

    static func replacingTableLinks(
        from markdown: String,
        replacement: (String) -> String
    ) -> String {
        replacingMatches(
            in: markdown,
            using: tableRegex,
            captureGroup: 2,
            fallbackGroup: 1,
            replacement: replacement
        )
    }

    static func removingImageMarkdown(from markdown: String) -> String {
        replacingImageMarkdown(from: markdown) { _ in "" }
    }

    static func replacingImageMarkdown(
        from markdown: String,
        replacement: (String) -> String
    ) -> String {
        replacingMatches(
            in: markdown,
            using: imageRegex,
            captureGroup: 1,
            fallbackGroup: nil,
            replacement: replacement
        )
    }

    // MARK: - Private

    private static func replacingMatches(
        in markdown: String,
        using regex: NSRegularExpression,
        captureGroup: Int,
        fallbackGroup: Int?,
        replacement: (String) -> String
    ) -> String {
        let ns = markdown as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: markdown, range: fullRange)
        guard !matches.isEmpty else { return markdown }

        var output = ""
        output.reserveCapacity(markdown.count)

        var cursor = 0
        for match in matches {
            let matchRange = match.range(at: 0)
            guard matchRange.location != NSNotFound else { continue }

            let prefixRange = NSRange(location: cursor, length: max(0, matchRange.location - cursor))
            if prefixRange.length > 0 {
                output += ns.substring(with: prefixRange)
            }

            let rawID = extractCapturedString(from: match, in: ns, group: captureGroup, fallbackGroup: fallbackGroup)
            output += replacement(normalizedResourceID(from: rawID))

            cursor = matchRange.location + matchRange.length
        }

        if cursor < ns.length {
            output += ns.substring(from: cursor)
        }

        return output
    }

    private static func extractCapturedString(
        from match: NSTextCheckingResult,
        in ns: NSString,
        group: Int,
        fallbackGroup: Int?
    ) -> String {
        if match.numberOfRanges > group {
            return ns.substring(with: match.range(at: group))
        }
        if let fallback = fallbackGroup, match.numberOfRanges > fallback {
            return ns.substring(with: match.range(at: fallback))
        }
        return ""
    }

    private static func normalizedResourceID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let unwrapped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
        let lastComponent = (unwrapped as NSString).lastPathComponent
        let withoutQuery = lastComponent.split(separator: "?", maxSplits: 1).first.map(String.init) ?? lastComponent
        let withoutFragment = withoutQuery.split(separator: "#", maxSplits: 1).first.map(String.init) ?? withoutQuery
        return withoutFragment
    }
}
