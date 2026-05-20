import Foundation
import os

extension MarkdownRenderPreparation {
    /// Process-wide compiled-regex cache. Compiling an `NSRegularExpression`
    /// is the single most expensive op in the prep pipeline (ICU parser
    /// allocation per call). The cache trims 30-50% off `prepareForRender`
    /// time on long messages.
    private static let regexCache = OSAllocatedUnfairLock<[String: NSRegularExpression]>(initialState: [:])

    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCache.withLock { dict in
            if let existing = dict[pattern] { return existing }
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
            dict[pattern] = compiled
            return compiled
        }
    }

    static func matches(_ pattern: String, in string: String) -> Bool {
        firstMatch(pattern: pattern, in: string) != nil
    }

    static func firstMatch(pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let regex = cachedRegex(pattern) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    static func replacing(pattern: String, in string: String, with template: String) -> String {
        guard let regex = cachedRegex(pattern) else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    static func replacingOutsideRanges(
        pattern: String,
        in string: String,
        protectedRanges: [Range<String.Index>],
        with template: String
    ) -> String {
        guard let regex = cachedRegex(pattern) else { return string }
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
