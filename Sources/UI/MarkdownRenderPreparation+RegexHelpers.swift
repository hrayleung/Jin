import Foundation

extension MarkdownRenderPreparation {
    static func matches(_ pattern: String, in string: String) -> Bool {
        firstMatch(pattern: pattern, in: string) != nil
    }

    static func firstMatch(pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    static func replacing(pattern: String, in string: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    /// Like `replacing(pattern:in:with:)` but skips matches whose range overlaps
    /// any of `protectedRanges`. Used by `MarkdownStructuralRepair` to avoid
    /// firing structural transforms on positions that the inline tokenizer
    /// recognized as part of matched emphasis or inline code.
    static func replacingOutsideRanges(
        pattern: String,
        in string: String,
        protectedRanges: [Range<String.Index>],
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let fullRange = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regex.matches(in: string, range: fullRange)
        guard !matches.isEmpty else { return string }

        var result = ""
        result.reserveCapacity(string.count + matches.count * 2)
        var cursor = string.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: string) else { continue }
            if protectedRanges.contains(where: { $0.overlaps(matchRange) }) {
                continue
            }
            if matchRange.lowerBound < cursor {
                continue
            }
            result.append(contentsOf: string[cursor..<matchRange.lowerBound])
            let replacement = regex.replacementString(
                for: match,
                in: string,
                offset: 0,
                template: template
            )
            result.append(replacement)
            cursor = matchRange.upperBound
        }
        result.append(contentsOf: string[cursor..<string.endIndex])
        return result
    }

    static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isLowercase }
    }

    static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isUppercase }
    }

    static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }
}
