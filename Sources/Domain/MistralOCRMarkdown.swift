import Foundation

enum MistralOCRMarkdown {
    // Matches Markdown image syntax: ![alt](target)
    // Captures `target` in group 1.
    // Note: Mistral OCR commonly emits placeholders like: ![img-0.jpeg](img-0.jpeg)
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)]+)\\)")

    static func referencedImageIDs(in markdown: String) -> [String] {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        return imageRegex
            .matches(in: markdown, range: range)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = ns.substring(with: match.range(at: 1))
                let normalized = normalizedImageID(from: raw)
                return normalized.isEmpty ? nil : normalized
            }
    }

    static func removingImageMarkdown(from markdown: String) -> String {
        replacingImageMarkdown(from: markdown) { _ in "" }
    }

    static func replacingImageMarkdown(
        from markdown: String,
        replacement: (String) -> String
    ) -> String {
        let ns = markdown as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = imageRegex.matches(in: markdown, range: fullRange)
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

            let rawID: String
            if match.numberOfRanges > 1 {
                rawID = ns.substring(with: match.range(at: 1))
            } else {
                rawID = ""
            }
            let normalized = normalizedImageID(from: rawID)
            output += replacement(normalized)

            cursor = matchRange.location + matchRange.length
        }

        if cursor < ns.length {
            output += ns.substring(from: cursor)
        }

        return output
    }

    private static func normalizedImageID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Common Markdown forms include: <img-0.jpeg>, "img-0.jpeg", 'img-0.jpeg'
        let unwrapped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
        let lastComponent = (unwrapped as NSString).lastPathComponent
        return lastComponent
    }
}
