import AppKit
import Foundation

enum CodeExecSyntaxHighlighter {
    private static let baseColor = NSColor.labelColor.withAlphaComponent(0.88)
    private static let keywordColor = NSColor.systemBlue.withAlphaComponent(0.9)
    private static let stringColor = NSColor.systemRed.withAlphaComponent(0.86)
    private static let commentColor = NSColor.secondaryLabelColor.withAlphaComponent(0.95)
    private static let numberColor = NSColor.systemPurple.withAlphaComponent(0.82)
    private static let functionColor = NSColor.systemTeal.withAlphaComponent(0.9)

    static func highlighted(_ text: String, language: CodeExecCodeLanguage?) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        guard text.count <= 20_000 else { return AttributedString(text) }

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: baseColor
            ]
        )
        let fullRange = NSRange(location: 0, length: attributed.length)

        let functionPattern = #"(?m)\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#
        apply(pattern: functionPattern, color: functionColor, to: attributed, range: fullRange)

        let keywordPattern = keywordPattern(for: language)
        apply(pattern: keywordPattern, color: keywordColor, to: attributed, range: fullRange)

        let numberPattern = #"(?<![\w.])\d+(?:\.\d+)?(?![\w.])"#
        apply(pattern: numberPattern, color: numberColor, to: attributed, range: fullRange)

        let stringPattern = #"(?s)\"\"\".*?\"\"\"|'''.*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        apply(pattern: stringPattern, color: stringColor, to: attributed, range: fullRange)

        let commentPattern = commentPattern(for: language)
        apply(pattern: commentPattern, color: commentColor, to: attributed, range: fullRange)

        return AttributedString(attributed)
    }

    private static func keywordPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript:
            return #"\b(await|async|break|case|catch|class|const|continue|default|else|export|false|finally|for|from|function|if|import|in|let|new|null|return|switch|throw|true|try|typeof|undefined|var|while)\b"#
        case .shell:
            return #"\b(case|do|done|elif|else|esac|export|fi|for|function|if|in|local|return|then|unset|while)\b"#
        case .swift:
            return #"\b(actor|async|await|case|class|enum|extension|false|for|func|if|import|in|let|nil|private|protocol|return|self|struct|switch|throw|true|var|while)\b"#
        case .python, .generic, .none:
            return #"\b(and|as|assert|break|class|continue|def|del|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#
        }
    }

    private static func commentPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript, .swift:
            return #"(?m)//.*$|/\*[\s\S]*?\*/"#
        case .shell, .python, .generic, .none:
            return #"(?m)#.*$"#
        }
    }

    private static func apply(
        pattern: String,
        color: NSColor,
        to attributed: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
