import Foundation

extension MarkdownRenderPreparation {
    static func repairLine(_ line: String) -> String {
        preserveInlineCode(in: line) { candidate in
            var normalized = candidate
            normalized = normalizeHeadingSpacing(normalized)
            normalized = insertBreaksBeforeEmbeddedHorizontalRules(normalized)
            normalized = insertBreaksBeforeEmbeddedHeadings(normalized)
            normalized = insertBreaksBeforeEmbeddedBullets(normalized)
            normalized = insertBreaksBeforeEmbeddedOrderedListMarkers(normalized)
            normalized = unescapeEscapedLeadingEmphasis(normalized)
            normalized = normalizeInlineTable(normalized)
            normalized = insertBreakBetweenHeadingAndBody(normalized)
            return normalized
        }
    }

    static func normalizeHeadingSpacing(_ line: String) -> String {
        let leadingWhitespaceCount = line.prefix(while: { $0 == " " }).count
        guard leadingWhitespaceCount <= 3 else { return line }

        let contentStart = line.index(line.startIndex, offsetBy: leadingWhitespaceCount)
        var hashIndex = contentStart
        var hashCount = 0

        while hashIndex < line.endIndex, line[hashIndex] == "#", hashCount < 7 {
            hashCount += 1
            hashIndex = line.index(after: hashIndex)
        }

        guard (1...6).contains(hashCount), hashIndex < line.endIndex else { return line }
        guard line[hashIndex] != " ", line[hashIndex] != "\t" else { return line }

        let leadingWhitespace = String(line[..<contentStart])
        let headingMarker = String(repeating: "#", count: hashCount)
        let remainder = line[hashIndex...]
        return leadingWhitespace + headingMarker + " " + remainder
    }

    static func insertBreaksBeforeEmbeddedHorizontalRules(_ line: String) -> String {
        replacing(
            pattern: #"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#,
            in: line,
            with: "\n$1\n"
        )
    }

    static func insertBreaksBeforeEmbeddedHeadings(_ line: String) -> String {
        replacing(
            pattern: #"(?<=\S)\s+(#{1,6})(?=[#\dA-Za-z\p{Han}])"#,
            in: line,
            with: "\n$1"
        )
    }

    static func insertBreaksBeforeEmbeddedBullets(_ line: String) -> String {
        replacing(
            pattern: #"(?<=\S)(?<![*+-])([-*+])\s+(?=(?:\*\*)?[\p{L}\p{N}])"#,
            in: line,
            with: "\n$1 "
        )
    }

    static func insertBreaksBeforeEmbeddedOrderedListMarkers(_ line: String) -> String {
        replacing(
            pattern: #"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#,
            in: line,
            with: "\n$1 "
        )
    }

    static func unescapeEscapedLeadingEmphasis(_ line: String) -> String {
        var normalized = line
        for marker in ["***", "**", "*"] {
            normalized = replacing(
                pattern: escapedLeadingEmphasisPattern(for: marker),
                in: normalized,
                with: "$1\(marker)$2\(marker)"
            )
        }
        return normalized
    }

    static func hasEscapedLeadingEmphasis(in line: String) -> Bool {
        ["***", "**", "*"].contains { marker in
            matches(escapedLeadingEmphasisPattern(for: marker), in: line)
        }
    }

    static func escapedLeadingEmphasisPattern(for marker: String) -> String {
        let escapedMarker = escapedEmphasisMarkerSequence(for: marker)
        return #"^(\s*(?:(?:[-*+•]|\d{1,2}[.)])\s+)?)"#
            + escapedMarker
            + #"(?=\S)([^\n]*?\S)"#
            + escapedMarker
            + #"(?=\s|$|[.,:;!?，。；：、）\)])"#
    }

    static func escapedEmphasisMarkerSequence(for marker: String) -> String {
        String(repeating: #"\\\*"#, count: marker.count)
    }

    static func insertBreakBetweenHeadingAndBody(_ line: String) -> String {
        let leadingWhitespace = String(line.prefix { $0.isWhitespace })
        let trimmedLeading = String(line.dropFirst(leadingWhitespace.count)).trimmingCharacters(in: .whitespaces)
        guard matches(#"^#{1,6}\s+"#, in: trimmedLeading),
              let splitIndex = headingBodySplitIndex(in: trimmedLeading) else {
            return line
        }

        let before = trimmedLeading[..<splitIndex].trimmingCharacters(in: .whitespaces)
        let after = trimmedLeading[splitIndex...].trimmingCharacters(in: .whitespaces)
        guard !before.isEmpty, !after.isEmpty else { return line }

        return leadingWhitespace + before + "\n" + after
    }

    static func headingBodySplitIndex(in line: String) -> String.Index? {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard let headingMatch = firstMatch(
            pattern: #"^#{1,6}\s+"#,
            in: trimmedLeading
        ) else { return nil }

        guard let headingRange = Range(headingMatch.range, in: trimmedLeading) else { return nil }
        let content = trimmedLeading[headingRange.upperBound...]
        guard content.count >= 16 else { return nil }

        var previousCharacter: Character?
        var index = content.startIndex

        while index < content.endIndex {
            let currentCharacter = content[index]
            let nextIndex = content.index(after: index)
            let nextCharacter = nextIndex < content.endIndex ? content[nextIndex] : nil

            if let previousCharacter,
               isLowercaseLetter(previousCharacter) || isDecimalDigit(previousCharacter),
               isUppercaseLetter(currentCharacter),
               nextCharacter.map(isLowercaseLetter) == true {
                let prefixCount = content.distance(from: content.startIndex, to: index)
                let suffixCount = content.distance(from: index, to: content.endIndex)
                if prefixCount >= 8, suffixCount >= 8 {
                    return index
                }
            }

            previousCharacter = currentCharacter
            index = nextIndex
        }

        return nil
    }
}
