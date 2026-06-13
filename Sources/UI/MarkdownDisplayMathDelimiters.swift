import Foundation

/// Shared line classifier for display-math regions (`$$ … $$` / `\[ … \]`).
///
/// Four walkers must agree on where a display-math region starts and ends —
/// `MarkdownExtensionPreprocessor` (converts regions to ```math fences),
/// `transformOutsideProtectedBlocks` (shields LaTeX from per-line repair),
/// `MarkdownInlineCompletion` and `unclosedInlineSignal` (must not treat
/// LaTeX as prose with unmatched emphasis). Before this classifier each had
/// its own "standalone `$$` line only" logic, which mis-handled the very
/// common LLM shapes `$$E=mc^2` (opener with content) and `E=mc^2 $$`
/// (closer with content): the leftover standalone `$$` was then read as an
/// *opener* and the entire rest of the document got buffered into one math
/// block — the "whole paragraphs disappear" bug.
///
/// `\[`-with-content is deliberately NOT an opener: `\[1\] 引用` style
/// escaped-bracket prose is too common to risk. Brackets only open on a
/// standalone `\[` line (unchanged), but DO support closer-with-content.
enum MarkdownDisplayMathDelimiters {
    enum Delimiter: Equatable {
        case dollars // $$ … $$
        case bracket // \[ … \]

        var closingToken: String {
            switch self {
            case .dollars: return "$$"
            case .bracket: return "\\]"
            }
        }
    }

    /// Role of a line encountered OUTSIDE any math region.
    enum OpeningRole: Equatable {
        case none
        /// Whole line is one `$$latex$$` region.
        case selfContained(latex: String)
        /// Line opens a region; `seed` is LaTeX already present on the
        /// opener line (`$$E=mc^2` → seed "E=mc^2").
        case opens(Delimiter, seed: String?)
    }

    /// Role of a line encountered INSIDE a math region.
    enum ClosingRole: Equatable {
        case notClosing
        /// Line closes the region. `content` is LaTeX preceding the closing
        /// token (`E=mc^2 $$`); `remainder` is prose following a leading
        /// closing token (`$$后文`).
        case closes(content: String?, remainder: String?)
    }

    /// Classify a whitespace-trimmed line outside any math region.
    static func openingRole(ofTrimmedLine trimmed: String) -> OpeningRole {
        if trimmed == "$$" { return .opens(.dollars, seed: nil) }
        if trimmed == "\\[" { return .opens(.bracket, seed: nil) }

        guard trimmed.hasPrefix("$$") else { return .none }
        let rest = String(trimmed.dropFirst(2))

        if rest.hasSuffix("$$"), rest.count >= 2 {
            let inner = String(rest.dropLast(2))
            // `$$a$$b$$` is ambiguous — leave it to the inline path.
            guard !inner.isEmpty, !inner.contains("$$") else { return .none }
            return .selfContained(latex: inner)
        }

        // Opener with trailing content: `$$E=mc^2`. If the rest contains
        // another `$$` the line is some inline mixture — leave it alone.
        guard !rest.isEmpty, !rest.contains("$$") else { return .none }
        return .opens(.dollars, seed: rest)
    }

    /// Classify a whitespace-trimmed line inside a math region opened with
    /// `delimiter`.
    static func closingRole(
        ofTrimmedLine trimmed: String,
        delimiter: Delimiter
    ) -> ClosingRole {
        let token = delimiter.closingToken
        if trimmed == token { return .closes(content: nil, remainder: nil) }

        if trimmed.hasPrefix(token) {
            // `$$后文` — close, remainder is prose.
            let remainder = String(trimmed.dropFirst(token.count))
            return .closes(content: nil, remainder: remainder.isEmpty ? nil : remainder)
        }

        if trimmed.hasSuffix(token) {
            let content = String(trimmed.dropLast(token.count))
            // `…\$$` — the first `$` is escaped, not a closing token.
            if delimiter == .dollars, content.hasSuffix("\\") { return .notClosing }
            let cleaned = content.trimmingCharacters(in: .whitespaces)
            return .closes(content: cleaned.isEmpty ? nil : cleaned, remainder: nil)
        }

        return .notClosing
    }
}
