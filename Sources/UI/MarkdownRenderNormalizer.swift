import Foundation

enum MarkdownRepairMode: String, Equatable, Sendable {
    case none
    case safe
    case full
}

struct NormalizedMarkdownResult: Equatable, Sendable {
    let text: String
    let didChange: Bool
    let repairMode: MarkdownRepairMode
    let anomalyScoreBefore: Int
    let anomalyScoreAfter: Int
    let preferHardBreaks: Bool
}

extension NormalizedMarkdownResult {
    static func passthrough(_ text: String) -> Self {
        Self(
            text: text,
            didChange: false,
            repairMode: .none,
            anomalyScoreBefore: 0,
            anomalyScoreAfter: 0,
            preferHardBreaks: false
        )
    }
}

enum MarkdownRenderNormalizer {
    private struct RepairProfile: Sendable {
        let allowHeadingBodySplit: Bool
        let preferHardBreaksWhenStreaming: Bool

        static let detected = RepairProfile(
            allowHeadingBodySplit: true,
            preferHardBreaksWhenStreaming: false
        )

        static let preferredModel = RepairProfile(
            allowHeadingBodySplit: true,
            preferHardBreaksWhenStreaming: true
        )
    }

    private static let preferredRepairModelIDs: Set<String> = [
        "deepseek-v4-flash",
        "deepseek-v4-pro",
        "kimi-k2.6",
        "moonshotai/kimi-k2.6",
        "@cf/moonshotai/kimi-k2.6",
        "fireworks/kimi-k2p6",
        "accounts/fireworks/models/kimi-k2p6",
        "fireworks/kimi-k2-instruct-0905",
        "accounts/fireworks/models/kimi-k2-instruct-0905",
        "moonshotai/kimi-k2-instruct-0905"
    ]

    static func shouldNormalize(modelID: String?) -> Bool {
        guard let canonicalID = canonicalModelID(modelID) else { return false }
        return preferredRepairModelIDs.contains(canonicalID)
    }

    static func normalize(_ markdown: String, modelID: String?) -> String {
        normalizeForRender(markdown, modelID: modelID, isStreaming: false).text
    }

    static func normalizeForRender(
        _ markdown: String,
        modelID: String?,
        isStreaming: Bool
    ) -> NormalizedMarkdownResult {
        guard !markdown.isEmpty else {
            return NormalizedMarkdownResult(
                text: markdown,
                didChange: false,
                repairMode: .none,
                anomalyScoreBefore: 0,
                anomalyScoreAfter: 0,
                preferHardBreaks: false
            )
        }

        let anomalyScoreBefore = anomalyScore(in: markdown)
        let preferredProfile = preferredRepairProfile(for: modelID)
        let profile = preferredProfile ?? (anomalyScoreBefore > 0 ? .detected : nil)

        guard let profile else {
            return NormalizedMarkdownResult(
                text: markdown,
                didChange: false,
                repairMode: .none,
                anomalyScoreBefore: anomalyScoreBefore,
                anomalyScoreAfter: anomalyScoreBefore,
                preferHardBreaks: false
            )
        }

        let safeText = repairMarkdown(markdown, mode: .safe, profile: profile)
        let safeScore = anomalyScore(in: safeText)

        var bestText = markdown
        var bestScore = anomalyScoreBefore
        var bestMode: MarkdownRepairMode = .none

        if safeText != markdown, safeScore <= anomalyScoreBefore || preferredProfile != nil {
            bestText = safeText
            bestScore = safeScore
            bestMode = .safe
        }

        if !isStreaming {
            let fullText = repairMarkdown(bestMode == .none ? markdown : safeText, mode: .full, profile: profile)
            let fullScore = anomalyScore(in: fullText)
            let fullCandidateChanged = fullText != markdown
            let shouldPreferFull = fullCandidateChanged && (
                fullScore < bestScore
                    || (preferredProfile != nil && fullScore <= bestScore)
            )

            if shouldPreferFull {
                bestText = fullText
                bestScore = fullScore
                bestMode = .full
            } else if bestMode == .safe, fullText == bestText {
                bestMode = .full
            }
        }

        if preferredProfile == nil, bestMode != .none, bestScore > anomalyScoreBefore {
            bestText = markdown
            bestScore = anomalyScoreBefore
            bestMode = .none
        }

        let preferHardBreaks = isStreaming && (
            bestScore > 0
                || (preferredProfile?.preferHardBreaksWhenStreaming == true && bestMode != .none)
        )

        return NormalizedMarkdownResult(
            text: bestText,
            didChange: bestText != markdown,
            repairMode: bestMode,
            anomalyScoreBefore: anomalyScoreBefore,
            anomalyScoreAfter: bestScore,
            preferHardBreaks: preferHardBreaks
        )
    }

    private static func preferredRepairProfile(for modelID: String?) -> RepairProfile? {
        guard let canonicalID = canonicalModelID(modelID) else { return nil }
        guard preferredRepairModelIDs.contains(canonicalID) else { return nil }
        return .preferredModel
    }

    private static func canonicalModelID(_ modelID: String?) -> String? {
        modelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func repairMarkdown(
        _ markdown: String,
        mode: MarkdownRepairMode,
        profile: RepairProfile
    ) -> String {
        let repaired = transformOutsideProtectedBlocks(in: markdown) { line in
            normalizeOutsideProtectedLine(line, mode: mode, profile: profile)
        }

        guard mode == .full else { return repaired }

        return normalizeBlockSpacing(in: repaired)
    }

    private static func normalizeOutsideProtectedLine(
        _ line: String,
        mode: MarkdownRepairMode,
        profile: RepairProfile
    ) -> String {
        preserveInlineCode(in: line) { candidate in
            var normalized = candidate
            normalized = normalizeHeadingSpacing(normalized)
            normalized = insertBreaksBeforeEmbeddedHorizontalRules(normalized)
            normalized = insertBreaksBeforeEmbeddedHeadings(normalized)
            normalized = insertBreaksBeforeEmbeddedBullets(normalized)
            normalized = insertBreaksBeforeEmbeddedOrderedListMarkers(normalized)
            normalized = normalizeInlineTable(normalized)

            if profile.allowHeadingBodySplit || mode == .full {
                normalized = insertBreakBetweenHeadingAndBody(normalized)
            }

            return normalized
        }
    }

    private static func transformOutsideProtectedBlocks(
        in markdown: String,
        transform: (String) -> String
    ) -> String {
        var output = ""
        output.reserveCapacity(markdown.count + 64)

        var activeFenceDelimiter: String?
        var insideDisplayMathBlock = false

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let fenceDelimiter = fenceDelimiter(in: trimmedLeading) {
                if activeFenceDelimiter == nil {
                    activeFenceDelimiter = fenceDelimiter
                } else if activeFenceDelimiter == fenceDelimiter {
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
            if matches(#"(?<=\S)(?:-\s+|\*\s+|\+\s+)(?=[\p{L}\p{N}])"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#, in: protectedLine) {
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
            pattern: #"(?<=\S)([-*+])\s+(?=[\p{L}\p{N}])"#,
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

    private static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }

        var normalized = line

        if let firstPipeIndex = normalized.firstIndex(of: "|") {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            if !prefix.isEmpty, looksLikeTableRow(suffix) {
                normalized = String(prefix) + "\n" + suffix
            }
        }

        normalized = replacing(
            pattern: #"(\|\s*[^|\n]+\s*(?:\|\s*[^|\n]+\s*)+\|)\s*(\|\s*[:\-]{3,})"#,
            in: normalized,
            with: "$1\n$2"
        )

        normalized = replacing(
            pattern: #"(\|\s*[:\-]{3,}\s*(?:\|\s*[:\-]{3,}\s*)+\|)\s*(\|)"#,
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

    private static func fenceDelimiter(in trimmedLeading: String) -> String? {
        if trimmedLeading.hasPrefix("```") { return "```" }
        if trimmedLeading.hasPrefix("~~~") { return "~~~" }
        return nil
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
            if !prefix.isEmpty, looksLikeTableRow(suffix) {
                return true
            }
        }

        if matches(#"(\|\s*[^|\n]+\s*(?:\|\s*[^|\n]+\s*)+\|)\s*(\|\s*[:\-]{3,})"#, in: line) {
            return true
        }

        return matches(#"(\|\s*[:\-]{3,}\s*(?:\|\s*[:\-]{3,}\s*)+\|)\s*(\|)"#, in: line)
    }

    private static func tableCells(in line: String) -> [String] {
        line
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { String($0) }
    }

    private static func isLikelySeparatorRow(_ line: String) -> Bool {
        guard looksLikeTableRow(line) else { return false }
        return tableCells(in: line).allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let scalars = trimmed.unicodeScalars
            guard !scalars.isEmpty else { return false }
            guard scalars.allSatisfy({ $0 == ":" || $0 == "-" || $0 == " " }) else { return false }
            let dashCount = scalars.filter { $0 == "-" }.count
            return dashCount >= 3
        }
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
