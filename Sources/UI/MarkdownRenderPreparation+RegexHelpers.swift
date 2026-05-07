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
