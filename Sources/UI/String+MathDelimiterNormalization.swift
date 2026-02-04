import Foundation
import Markdown
@_spi(MarkdownMath) import MarkdownView

extension String {
    func normalizingMathDelimitersForMarkdownView() -> String {
        // MarkdownView's display-math rendering is implemented via block directives (`@math(...)`).
        // If display math appears inside a paragraph, the directive can be parsed as plain text,
        // leaking the UUID into the UI. We pre-normalize the text so display math sits in its own
        // block (blank lines around it) before handing it to MarkdownView.
        let normalized = normalizingInlineMathDelimiters()
        return normalized.normalizingDisplayMathBlocksForMarkdownView()
    }

    func normalizingInlineMathDelimiters() -> String {
        self
            .replacingOccurrences(of: "＄", with: "$") // U+FF04 FULLWIDTH DOLLAR SIGN
            .replacingOccurrences(of: "﹩", with: "$") // U+FE69 SMALL DOLLAR SIGN
            .replacingOccurrences(of: "＼", with: "\\") // U+FF3C FULLWIDTH REVERSE SOLIDUS
            .replacingOccurrences(of: "﹨", with: "\\") // U+FE68 SMALL REVERSE SOLIDUS
            .replacingOccurrences(of: "∖", with: "\\") // U+2216 SET MINUS (sometimes used as backslash)
    }
}

private extension String {
    func normalizingDisplayMathBlocksForMarkdownView() -> String {
        // Fast path: only run the parser work if we see likely display-math delimiters.
        if !contains("$$")
            && !contains("\\[")
            && !contains("\\begin{equation}")
            && !contains("\\begin{equation*}") {
            return self
        }

        // Exclude fenced/indented code blocks, so we don't rewrite code samples that happen to
        // include TeX-like delimiters.
        let document = Document(parsing: self, options: [.parseBlockDirectives])
        var extractor = CodeBlockRangeExtractor()
        extractor.visit(document)

        let allowedRanges = extractor.parsableRanges(in: self)
        var displayMathRanges: [Range<String.Index>] = []
        for allowedRange in allowedRanges {
            let segment = self[allowedRange]
            let parser = MathParser(text: segment)
            for math in parser.mathRepresentations where !math.kind.isInlineMath {
                displayMathRanges.append(math.range)
            }
        }

        guard !displayMathRanges.isEmpty else { return self }

        var text = self
        for range in displayMathRanges
            .sorted(by: { $0.lowerBound < $1.lowerBound })
            .reversed() {
            let (replacementRange, replacement) = text.replacementByIsolatingDisplayMathBlock(range: range)
            text.replaceSubrange(replacementRange, with: replacement)
        }
        return text
    }

    func replacementByIsolatingDisplayMathBlock(
        range: Range<String.Index>
    ) -> (Range<String.Index>, String) {
        let mathText = String(self[range])
        let mathStart = range.lowerBound
        let mathEnd = range.upperBound

        let lineStart = lineStartIndex(before: mathStart)
        let linePrefix = self[lineStart..<mathStart]
        let prefixHasNonWhitespace = linePrefix.contains { !$0.isInlineWhitespace }

        var replacementRange = range
        var prefix = ""
        var leadingWhitespace = ""

        if prefixHasNonWhitespace {
            // Display math starts mid-line -> force a paragraph break.
            prefix = "\n\n"
        } else {
            // Display math starts at beginning of the line (possibly indented).
            if lineStart != startIndex {
                let previousLineEndNewline = index(before: lineStart)
                let previousLineRange = lineRange(endingAtNewline: previousLineEndNewline)
                let previousLine = self[previousLineRange]

                if !previousLine.isBlankLine {
                    // Add one newline so we get a blank line between text and the math block.
                    prefix = "\n"

                    // Preserve indentation (important for lists/quotes) by including it in the replacement.
                    if !linePrefix.isEmpty {
                        replacementRange = lineStart..<mathEnd
                        leadingWhitespace = String(linePrefix)
                    }
                }
            }
        }

        let lineEndNewlineOrEnd = lineEndIndex(after: mathEnd)
        let lineSuffix = self[mathEnd..<lineEndNewlineOrEnd]
        let suffixHasNonWhitespace = lineSuffix.contains { !$0.isInlineWhitespace }

        var suffix = ""
        if suffixHasNonWhitespace {
            // Display math ends mid-line -> force a paragraph break.
            suffix = "\n\n"
        } else if lineEndNewlineOrEnd != endIndex {
            // There is a newline after the math. Ensure the next line is blank.
            let newlineIndex = lineEndNewlineOrEnd
            let nextLineStart = index(after: newlineIndex)
            if nextLineStart != endIndex {
                let nextLineEndNewlineOrEnd = self[nextLineStart...].firstIndex(of: "\n") ?? endIndex
                let nextLine = self[nextLineStart..<nextLineEndNewlineOrEnd]
                if !nextLine.isBlankLine {
                    suffix = "\n"
                }
            }
        }

        return (replacementRange, prefix + leadingWhitespace + mathText + suffix)
    }

    func lineStartIndex(before index: String.Index) -> String.Index {
        guard index != startIndex else { return startIndex }
        if let newline = self[..<index].lastIndex(of: "\n") {
            return self.index(after: newline)
        }
        return startIndex
    }

    func lineEndIndex(after index: String.Index) -> String.Index {
        guard index != endIndex else { return endIndex }
        if let newline = self[index...].firstIndex(of: "\n") {
            return newline
        }
        return endIndex
    }

    func lineRange(endingAtNewline newline: String.Index) -> Range<String.Index> {
        if let previousNewline = self[..<newline].lastIndex(of: "\n") {
            let start = index(after: previousNewline)
            return start..<newline
        }
        return startIndex..<newline
    }
}

private extension Character {
    var isInlineWhitespace: Bool {
        self == " " || self == "\t" || self == "\r"
    }
}

private extension Substring {
    var isBlankLine: Bool {
        allSatisfy(\.isInlineWhitespace)
    }
}

private extension MathParser.MathRepresentation.Kind {
    var isInlineMath: Bool {
        switch self {
        case .inlineEquation, .inlineParenthesesEquation:
            return true
        default:
            return false
        }
    }
}

private struct CodeBlockRangeExtractor: MarkupWalker {
    private var excludedRanges: [Range<SourceLocation>] = []

    func parsableRanges(in text: String) -> [Range<String.Index>] {
        var allowedRanges: [Range<String.Index>] = []
        let excludedRanges = self.excludedRanges.map {
            ($0.lowerBound.index(in: text)..<$0.upperBound.index(in: text))
        }

        let fullRange = text.startIndex..<text.endIndex
        let sortedExcluded = excludedRanges.sorted { $0.lowerBound < $1.lowerBound }
        var currentStart = fullRange.lowerBound

        for ex in sortedExcluded {
            if currentStart < ex.lowerBound {
                allowedRanges.append(currentStart..<ex.lowerBound)
            }
            currentStart = ex.upperBound
        }
        if currentStart < fullRange.upperBound {
            allowedRanges.append(currentStart..<fullRange.upperBound)
        }
        return allowedRanges
    }

    mutating func defaultVisit(_ markup: any Markup) {
        descendInto(markup)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = codeBlock.range else { return }
        self.excludedRanges.append(range)
    }
}

private extension SourceLocation {
    func index(in string: String) -> String.Index {
        var idx = string.startIndex
        var currentLine = 1
        while currentLine < self.line && idx < string.endIndex {
            if string[idx] == "\n" {
                currentLine += 1
            }
            idx = string.index(after: idx)
        }
        guard let utf8LineStart = idx.samePosition(in: string.utf8) else {
            return string.endIndex
        }
        let byteOffset = self.column - 1
        let targetUtf8Index = string.utf8.index(
            utf8LineStart,
            offsetBy: byteOffset,
            limitedBy: string.utf8.endIndex
        ) ?? string.utf8.endIndex
        return targetUtf8Index.samePosition(in: string) ?? string.endIndex
    }
}
