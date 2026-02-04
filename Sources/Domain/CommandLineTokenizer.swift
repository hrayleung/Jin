import Foundation

struct CommandLineTokenizer {
    static func tokenize(_ commandLine: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuotes = false
        var inDoubleQuotes = false
        var escapeNext = false

        for scalar in commandLine.unicodeScalars {
            let ch = Character(scalar)

            if escapeNext {
                current.append(ch)
                escapeNext = false
                continue
            }

            if ch == "\\" && !inSingleQuotes {
                escapeNext = true
                continue
            }

            if ch == "\"" && !inSingleQuotes {
                inDoubleQuotes.toggle()
                continue
            }

            if ch == "'" && !inDoubleQuotes {
                inSingleQuotes.toggle()
                continue
            }

            if ch.isWhitespace && !inSingleQuotes && !inDoubleQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(ch)
        }

        if escapeNext {
            throw CommandLineTokenizerError.danglingEscape
        }

        if inSingleQuotes || inDoubleQuotes {
            throw CommandLineTokenizerError.unterminatedQuote
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    static func render(_ tokens: [String]) -> String {
        tokens.map(renderToken).joined(separator: " ")
    }

    private static func renderToken(_ token: String) -> String {
        if token.isEmpty {
            return "\"\""
        }

        let needsQuotes = token.contains(where: { $0.isWhitespace }) || token.contains("\"") || token.contains("'") || token.contains("\\")
        guard needsQuotes else { return token }

        var escaped = ""
        escaped.reserveCapacity(token.count)
        for ch in token {
            switch ch {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            default:
                escaped.append(ch)
            }
        }

        return "\"\(escaped)\""
    }
}

enum CommandLineTokenizerError: Error, LocalizedError {
    case unterminatedQuote
    case danglingEscape

    var errorDescription: String? {
        switch self {
        case .unterminatedQuote:
            return "Unterminated quote in command line."
        case .danglingEscape:
            return "Dangling escape character in command line."
        }
    }
}

