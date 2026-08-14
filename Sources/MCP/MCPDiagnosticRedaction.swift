import Foundation

enum MCPDiagnosticRedaction {
    static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text
        result = replaceMatches(
            in: result,
            pattern: #"(?i)Bearer\s+\S+"#,
            replacement: "Bearer [redacted]"
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)("Authorization"\s*:\s*")[^"]+(")"#,
            replacement: "$1[redacted]$2"
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)(Authorization\s*:\s*)\S+"#,
            replacement: "$1[redacted]"
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)\bas_sk_[A-Za-z0-9]+\b"#,
            replacement: "[redacted]"
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)\bsk-[A-Za-z0-9_-]{8,}\b"#,
            replacement: "[redacted]"
        )
        return result
    }

    static func redactTokens(_ tokens: [String]) -> [String] {
        var redacted: [String] = []
        redacted.reserveCapacity(tokens.count)

        var redactNext = false
        for token in tokens {
            if redactNext {
                redacted.append(redact(token))
                redactNext = false
                continue
            }

            let lower = token.lowercased()
            if lower == "--header" || lower == "-h" {
                redacted.append(token)
                redactNext = true
                continue
            }

            redacted.append(redact(token))
        }

        return redacted
    }

    private static func replaceMatches(in text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
