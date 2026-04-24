import Foundation

enum MarkdownRenderNormalizer {
    static func shouldNormalize(modelID: String?) -> Bool {
        switch modelID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deepseek-v4-flash", "deepseek-v4-pro":
            return true
        default:
            return false
        }
    }

    static func normalize(_ markdown: String, modelID: String?) -> String {
        guard shouldNormalize(modelID: modelID) else { return markdown }
        return normalizeDeepSeekV4(markdown)
    }

    static func normalizeDeepSeekV4(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return markdown }

        var output = ""
        output.reserveCapacity(markdown.count + 64)
        var outsideFence = true

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)

            if isFenceBoundary(trimmedLeading) {
                outsideFence.toggle()
                output.append(line)
                output.append("\n")
                continue
            }

            let normalizedLine = outsideFence ? normalizeOutsideFence(line) : line
            output.append(normalizedLine)
            output.append("\n")
        }

        if !markdown.hasSuffix("\n") {
            output.removeLast()
        }

        return output
    }

    private static func normalizeOutsideFence(_ line: String) -> String {
        var normalized = line
        normalized = normalizeHeadingSpacing(normalized)
        normalized = insertBreaksBeforeEmbeddedHorizontalRules(normalized)
        normalized = insertBreaksBeforeEmbeddedHeadings(normalized)
        normalized = insertBreaksBeforeEmbeddedBullets(normalized)
        normalized = normalizeInlineTable(normalized)
        return normalized
    }

    private static func normalizeHeadingSpacing(_ line: String) -> String {
        replacing(
            pattern: #"(^|\n)( {0,3}#{1,6})(?=\S)"#,
            in: line,
            with: "$1$2 "
        )
    }

    private static func insertBreaksBeforeEmbeddedHorizontalRules(_ line: String) -> String {
        replacing(
            pattern: #"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#,
            in: line,
            with: "\n$1\n"
        )
    }

    private static func insertBreaksBeforeEmbeddedHeadings(_ line: String) -> String {
        replacing(
            pattern: #"(?<!^)(?<!\n)\s+(#{1,6})(?=[#\dA-Za-z])"#,
            in: line,
            with: "\n$1"
        )
    }

    private static func insertBreaksBeforeEmbeddedBullets(_ line: String) -> String {
        replacing(
            pattern: #"(?<=\S)-\s+(?=[A-Z0-9])"#,
            in: line,
            with: "\n- "
        )
    }

    private static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }

        let normalizedSeparator = replacing(
            pattern: #"\|\s*-{3,}\s*\|\s*-{3,}\s*\|+"#,
            in: line,
            with: "\n|---|---|"
        )

        return replacing(
            pattern: #"(?<!^)(?<!\n)\s+(\|---\|)"#,
            in: normalizedSeparator,
            with: "\n$1"
        )
    }

    private static func isFenceBoundary(_ trimmedLeading: String) -> Bool {
        trimmedLeading.hasPrefix("```") || trimmedLeading.hasPrefix("~~~")
    }

    private static func replacing(pattern: String, in string: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }
}
