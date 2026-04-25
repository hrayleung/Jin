import Foundation

enum MarkdownRepairMode: String, Equatable, Sendable {
    case none
    case repaired
}

struct MarkdownPreparationDiagnostics: Equatable, Sendable {
    let repairMode: MarkdownRepairMode
    let anomalyScoreBefore: Int
    let anomalyScoreAfter: Int
}

struct PreparedMarkdownResult: Equatable, Sendable {
    let text: String
    let didChange: Bool
    let diagnostics: MarkdownPreparationDiagnostics
}

extension PreparedMarkdownResult {
    static func passthrough(_ text: String) -> Self {
        Self(
            text: text,
            didChange: false,
            diagnostics: MarkdownPreparationDiagnostics(
                repairMode: .none,
                anomalyScoreBefore: 0,
                anomalyScoreAfter: 0
            )
        )
    }
}

enum MarkdownRenderPreparation {
    private struct FenceDelimiter {
        let marker: Character
        let length: Int
    }

    static func prepareForRender(_ markdown: String, isStreaming: Bool) -> PreparedMarkdownResult {
        guard !markdown.isEmpty else {
            return .passthrough(markdown)
        }

        let scoreBefore = anomalyScore(in: markdown)
        guard scoreBefore > 0 else {
            return PreparedMarkdownResult(
                text: markdown,
                didChange: false,
                diagnostics: MarkdownPreparationDiagnostics(
                    repairMode: .none,
                    anomalyScoreBefore: scoreBefore,
                    anomalyScoreAfter: scoreBefore
                )
            )
        }

        let repaired = repairMarkdown(markdown, isStreaming: isStreaming)
        let scoreAfter = anomalyScore(in: repaired)
        let shouldUseRepair = repaired != markdown && scoreAfter <= scoreBefore
        let output = shouldUseRepair ? repaired : markdown

        return PreparedMarkdownResult(
            text: output,
            didChange: output != markdown,
            diagnostics: MarkdownPreparationDiagnostics(
                repairMode: output == markdown ? .none : .repaired,
                anomalyScoreBefore: scoreBefore,
                anomalyScoreAfter: output == markdown ? scoreBefore : scoreAfter
            )
        )
    }

    static func prepare(_ markdown: String) -> String {
        prepareForRender(markdown, isStreaming: false).text
    }

    private static func repairMarkdown(_ markdown: String, isStreaming: Bool) -> String {
        let repairedLines = transformOutsideProtectedBlocks(in: markdown) { line in
            repairLine(line)
        }

        return isStreaming ? repairedLines : normalizeBlockSpacing(in: repairedLines)
    }

    private static func repairLine(_ line: String) -> String {
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

    private static func transformOutsideProtectedBlocks(
        in markdown: String,
        transform: (String) -> String
    ) -> String {
        var output = ""
        output.reserveCapacity(markdown.count + 64)

        var activeFenceDelimiter: FenceDelimiter?
        var insideDisplayMathBlock = false

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let fenceDelimiter = fenceDelimiter(in: trimmedLeading) {
                if activeFenceDelimiter == nil {
                    activeFenceDelimiter = fenceDelimiter
                } else if isClosingFenceLine(trimmedLeading, for: activeFenceDelimiter!) {
                    activeFenceDelimiter = nil
                }
                output.append(line)
                output.append("\n")
                continue
            }

            if activeFenceDelimiter != nil {
                output.append(line)
                output.append("\n")
                continue
            }

            if isStandaloneDisplayMathDelimiter(trimmed) {
                insideDisplayMathBlock.toggle()
                output.append(line)
                output.append("\n")
                continue
            }

            if insideDisplayMathBlock || shouldLeaveHTMLLineUntouched(trimmedLeading) {
                output.append(line)
                output.append("\n")
                continue
            }

            output.append(transform(line))
            output.append("\n")
        }

        if !markdown.hasSuffix("\n"), !output.isEmpty {
            output.removeLast()
        }

        return output
    }

    private static func anomalyScore(in markdown: String) -> Int {
        var score = 0

        _ = transformOutsideProtectedBlocks(in: markdown) { line in
            let protectedLine = preserveInlineCode(in: line) { $0 }

            if matches(#"^( {0,3}#{1,6})(?=\S)"#, in: protectedLine) {
                score += 3
            }
            if matches(#"(?<=\S)\s+(#{1,6})(?=[#\dA-Za-z\p{Han}])"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=\S)(?<![*+-])(?:-\s+(?=(?:\*\*)?[\p{L}\p{N}])|\*\s+(?=[\p{L}\p{N}])|\+\s+(?=[\p{L}\p{N}]))"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#, in: protectedLine) {
                score += 1
            }
            if hasEscapedLeadingEmphasis(in: protectedLine) {
                score += 1
            }
            if matches(#"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#, in: protectedLine) {
                score += 2
            }
            if lineHasInlineTableBreakage(protectedLine) {
                score += 2
            }
            if headingBodySplitIndex(in: protectedLine) != nil {
                score += 1
            }

            return protectedLine
        }

        return score
    }

    private static func normalizeHeadingSpacing(_ line: String) -> String {
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

    private static func insertBreaksBeforeEmbeddedHorizontalRules(_ line: String) -> String {
        replacing(
            pattern: #"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#,
            in: line,
            with: "\n$1\n"
        )
    }

    private static func insertBreaksBeforeEmbeddedHeadings(_ line: String) -> String {
        replacing(
            pattern: #"(?<=\S)\s+(#{1,6})(?=[#\dA-Za-z\p{Han}])"#,
            in: line,
            with: "\n$1"
        )
    }

    private static func insertBreaksBeforeEmbeddedBullets(_ line: String) -> String {
        replacing(
            pattern: #"(?<=\S)(?<![*+-])([-*+])\s+(?=(?:\*\*)?[\p{L}\p{N}])"#,
            in: line,
            with: "\n$1 "
        )
    }

    private static func insertBreaksBeforeEmbeddedOrderedListMarkers(_ line: String) -> String {
        replacing(
            pattern: #"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#,
            in: line,
            with: "\n$1 "
        )
    }

    private static func unescapeEscapedLeadingEmphasis(_ line: String) -> String {
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

    private static func hasEscapedLeadingEmphasis(in line: String) -> Bool {
        ["***", "**", "*"].contains { marker in
            matches(escapedLeadingEmphasisPattern(for: marker), in: line)
        }
    }

    private static func escapedLeadingEmphasisPattern(for marker: String) -> String {
        let escapedMarker = escapedEmphasisMarkerSequence(for: marker)
        return #"^(\s*(?:(?:[-*+•]|\d{1,2}[.)])\s+)?)"#
            + escapedMarker
            + #"(?=\S)([^\n]*?\S)"#
            + escapedMarker
            + #"(?=\s|$|[.,:;!?，。；：、）\)])"#
    }

    private static func escapedEmphasisMarkerSequence(for marker: String) -> String {
        String(repeating: #"\\\*"#, count: marker.count)
    }

    private static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }

        var normalized = line

        if let firstPipeIndex = normalized.firstIndex(of: "|") {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            if !prefix.isEmpty, looksLikeTableRow(suffix), !looksLikeParagraphWithPipes(prefix) {
                normalized = String(prefix) + "\n" + suffix
            }
        }

        normalized = replacing(
            pattern: #"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#,
            in: normalized,
            with: "$1\n$2"
        )

        normalized = replacing(
            pattern: #"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#,
            in: normalized,
            with: "$1\n$2"
        )

        return normalized
    }

    private static func insertBreakBetweenHeadingAndBody(_ line: String) -> String {
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

    private static func normalizeBlockSpacing(in markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return markdown }

        var output: [String] = []
        output.reserveCapacity(lines.count + 8)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousTrimmed = output.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if shouldInsertBlankLine(before: trimmed, previous: previousTrimmed) {
                output.append("")
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    private static func shouldInsertBlankLine(before current: String, previous: String) -> Bool {
        guard !current.isEmpty, !previous.isEmpty else { return false }

        if isHeadingLine(current) || isThematicBreakLine(current) {
            return !isHeadingLine(previous) && !isThematicBreakLine(previous)
        }

        if isListMarkerLine(current) {
            return !isListMarkerLine(previous)
                && !isHeadingLine(previous)
                && !isThematicBreakLine(previous)
        }

        if looksLikeTableRow(current), !looksLikeTableRow(previous) {
            return !isListMarkerLine(previous)
        }

        return false
    }

    private static func headingBodySplitIndex(in line: String) -> String.Index? {
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

    private static func preserveInlineCode(
        in line: String,
        transform: (String) -> String
    ) -> String {
        let characters = Array(line)
        guard characters.contains("`") else { return transform(line) }

        var placeholderIndex = 0
        var index = 0
        var sanitized = ""
        var placeholders: [(placeholder: String, content: String)] = []
        sanitized.reserveCapacity(line.count)

        while index < characters.count {
            if characters[index] != "`" {
                sanitized.append(characters[index])
                index += 1
                continue
            }

            let start = index
            var tickCount = 0
            while index < characters.count, characters[index] == "`" {
                tickCount += 1
                index += 1
            }

            var searchIndex = index
            var matchingStart: Int?

            while searchIndex < characters.count {
                if characters[searchIndex] != "`" {
                    searchIndex += 1
                    continue
                }

                var candidateCount = 0
                while searchIndex + candidateCount < characters.count,
                      characters[searchIndex + candidateCount] == "`" {
                    candidateCount += 1
                }

                if candidateCount == tickCount {
                    matchingStart = searchIndex
                    break
                }

                searchIndex += candidateCount
            }

            guard let matchingStart else {
                sanitized.append(contentsOf: String(characters[start..<index]))
                continue
            }

            let matchingEnd = matchingStart + tickCount
            let placeholder = "\u{F0000}JIN_CODE_\(placeholderIndex)\u{F0001}"
            placeholderIndex += 1
            placeholders.append((placeholder, String(characters[start..<matchingEnd])))
            sanitized.append(placeholder)
            index = matchingEnd
        }

        var transformed = transform(sanitized)
        for entry in placeholders {
            transformed = transformed.replacingOccurrences(of: entry.placeholder, with: entry.content)
        }
        return transformed
    }

    private static func shouldLeaveHTMLLineUntouched(_ trimmedLeading: String) -> Bool {
        guard !trimmedLeading.isEmpty else { return false }
        return trimmedLeading.hasPrefix("<")
            || trimmedLeading.hasPrefix("<!--")
    }

    private static func isStandaloneDisplayMathDelimiter(_ trimmed: String) -> Bool {
        trimmed == "$$" || trimmed == "\\[" || trimmed == "\\]"
    }

    private static func fenceDelimiter(in trimmedLeading: String) -> FenceDelimiter? {
        guard let marker = trimmedLeading.first, marker == "`" || marker == "~" else {
            return nil
        }

        let length = trimmedLeading.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return FenceDelimiter(marker: marker, length: length)
    }

    private static func isClosingFenceLine(_ trimmedLeading: String, for opening: FenceDelimiter) -> Bool {
        guard let closing = fenceDelimiter(in: trimmedLeading),
              closing.marker == opening.marker,
              closing.length >= opening.length else {
            return false
        }

        let rest = trimmedLeading.dropFirst(closing.length)
        return rest.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.hasSuffix("|") else {
            return false
        }

        let cells = tableCells(in: trimmed)
        return cells.count >= 2
    }

    private static func lineHasInlineTableBreakage(_ line: String) -> Bool {
        guard line.contains("|") else { return false }

        if let firstPipeIndex = line.firstIndex(of: "|") {
            let prefix = line[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(line[firstPipeIndex...])
            if !prefix.isEmpty, looksLikeTableRow(suffix), !looksLikeParagraphWithPipes(prefix) {
                return true
            }
        }

        if matches(#"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#, in: line) {
            return true
        }

        return matches(#"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#, in: line)
    }

    private static func tableCells(in line: String) -> [String] {
        line
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { String($0) }
    }

    private static func looksLikeParagraphWithPipes(_ prefix: String) -> Bool {
        prefix.contains(".") || prefix.contains(":") || prefix.contains("：") || prefix.split(separator: " ").count > 5
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        matches(#"^#{1,6}\s+\S"#, in: line)
    }

    private static func isThematicBreakLine(_ line: String) -> Bool {
        matches(#"^(?:---+|\*\*\*+|___+)$"#, in: line)
    }

    private static func isListMarkerLine(_ line: String) -> Bool {
        matches(#"^(?:[-*+]\s+|\d{1,2}[.)]\s+)"#, in: line)
    }

    private static func matches(_ pattern: String, in string: String) -> Bool {
        firstMatch(pattern: pattern, in: string) != nil
    }

    private static func firstMatch(pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private static func replacing(pattern: String, in string: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isLowercase }
    }

    private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isUppercase }
    }

    private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }
}
