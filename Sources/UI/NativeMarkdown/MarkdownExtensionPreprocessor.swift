import Foundation

/// Pre-processes raw markdown to surface math regions for the native walker.
/// `swift-markdown` does not recognise `$...$` / `$$...$$` / `\[...\]`, so
/// display-math regions are substituted with fenced code blocks tagged
/// `math`, which `MarkdownASTWalker` routes to `.mathBlock`.
///
/// Inline math (`$x$`) is preserved as literal text for V1 — see the plan's
/// "Risks" section. ```mermaid``` fenced blocks need no preprocessing; the
/// walker routes them by language.
enum MarkdownExtensionPreprocessor {
    static func preprocess(_ source: String) -> String {
        guard source.contains("$$") || source.contains("\\[") else { return source }

        var output = ""
        output.reserveCapacity(source.count + 32)

        var activeFenceMarker: Character?
        var activeFenceLength = 0
        var displayMathBuffer: [String]?
        var displayMathDelimiter: String?

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)

            // Inside a regular code fence — pass through.
            if let marker = activeFenceMarker {
                output.append(line)
                output.append("\n")
                if isFenceLine(trimmedLeading, marker: marker, minLength: activeFenceLength) {
                    activeFenceMarker = nil
                    activeFenceLength = 0
                }
                continue
            }

            // Inside a multi-line display-math block — collect until close.
            if displayMathBuffer != nil {
                if let closer = displayMathDelimiter, isDisplayMathCloser(trimmed, opener: closer) {
                    emitMathBlock(buffer: displayMathBuffer!, into: &output)
                    displayMathBuffer = nil
                    displayMathDelimiter = nil
                } else {
                    displayMathBuffer?.append(line)
                }
                continue
            }

            // Detect opening of a regular code fence.
            if let (marker, length) = openingFenceLength(trimmedLeading) {
                activeFenceMarker = marker
                activeFenceLength = length
                output.append(line)
                output.append("\n")
                continue
            }

            // Self-contained single-line display math: `$$x^2$$`.
            if let inlineDisplay = singleLineDisplayMath(trimmed) {
                emitMathBlock(buffer: [inlineDisplay], into: &output)
                continue
            }

            // Open a multi-line display-math block (`$$` or `\[`).
            if trimmed == "$$" {
                displayMathBuffer = []
                displayMathDelimiter = "$$"
                continue
            }
            if trimmed == "\\[" {
                displayMathBuffer = []
                displayMathDelimiter = "\\]"
                continue
            }

            output.append(line)
            output.append("\n")
        }

        // If a math block was never closed (incomplete during streaming),
        // emit what we have so far — the user still sees their LaTeX.
        if let leftover = displayMathBuffer, !leftover.isEmpty {
            emitMathBlock(buffer: leftover, into: &output)
        }

        if !source.hasSuffix("\n"), output.hasSuffix("\n") {
            output.removeLast()
        }
        return output
    }

    private static func emitMathBlock(buffer: [String], into output: inout String) {
        let latex = buffer.joined(separator: "\n")
        if !output.isEmpty, !output.hasSuffix("\n") {
            output.append("\n")
        }
        output.append("```math\n")
        output.append(latex)
        if !latex.hasSuffix("\n") { output.append("\n") }
        output.append("```\n")
    }

    private static func singleLineDisplayMath(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
        let latex = String(trimmed[start..<end])
        return latex.isEmpty ? nil : latex
    }

    private static func isDisplayMathCloser(_ trimmed: String, opener: String) -> Bool {
        trimmed == opener
    }

    private static func openingFenceLength(_ trimmedLeading: String) -> (Character, Int)? {
        guard let first = trimmedLeading.first, first == "`" || first == "~" else { return nil }
        let length = trimmedLeading.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        return (first, length)
    }

    private static func isFenceLine(_ trimmedLeading: String, marker: Character, minLength: Int) -> Bool {
        guard let first = trimmedLeading.first, first == marker else { return false }
        let length = trimmedLeading.prefix(while: { $0 == marker }).count
        guard length >= minLength else { return false }
        let rest = trimmedLeading.dropFirst(length)
        return rest.allSatisfy { $0 == " " || $0 == "\t" }
    }
}
