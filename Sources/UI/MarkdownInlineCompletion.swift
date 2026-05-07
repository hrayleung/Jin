import Foundation

/// Auto-closes unclosed inline emphasis / inline code / fenced code blocks
/// at paragraph & document boundaries. This is the streaming-completion pass
/// every mainstream LLM chat renderer applies (ChatGPT, Vercel AI SDK's
/// `streamdown`, etc.) so partial output never flashes literal asterisks
/// while waiting for the rest of a stream.
///
/// Runs after per-line structural repair. No-op for clean input.
enum MarkdownInlineCompletion {
    static func completeUnclosedInlineMarkers(in markdown: String) -> String {
        guard !markdown.isEmpty else { return markdown }

        let rawLines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var paragraph: [String] = []
        var fenceState: FenceState?
        var insideDisplayMath = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: "\n")
            let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: joined)

            if unmatched.isEmpty {
                output.append(contentsOf: paragraph)
            } else {
                // Close in LIFO order (most recent open first).
                let closures = unmatched.reversed().map { $0.marker }.joined()
                var lastLine = paragraph.removeLast()
                while let last = lastLine.last, last.isWhitespace {
                    lastLine.removeLast()
                }
                paragraph.append(lastLine + closures)
                output.append(contentsOf: paragraph)
            }
            paragraph.removeAll(keepingCapacity: true)
        }

        for line in rawLines {
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            let trimmedFull = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Inside a fenced code block: pass through; only watch for closer.
            if let active = fenceState {
                output.append(line)
                if isClosingFenceLine(trimmedLeading, active: active) {
                    fenceState = nil
                }
                continue
            }

            // Display math delimiters toggle a protected block.
            if trimmedFull == "$$" || trimmedFull == "\\[" || trimmedFull == "\\]" {
                flushParagraph()
                output.append(line)
                insideDisplayMath.toggle()
                continue
            }
            if insideDisplayMath {
                output.append(line)
                continue
            }

            // Fence opening.
            if let opening = fenceOpening(in: trimmedLeading) {
                flushParagraph()
                fenceState = opening
                output.append(line)
                continue
            }

            // HTML / comment lines pass through; they bound a paragraph.
            if trimmedLeading.hasPrefix("<") || trimmedLeading.hasPrefix("<!--") {
                flushParagraph()
                output.append(line)
                continue
            }

            // Blank line ends the current paragraph.
            if trimmedLeading.isEmpty {
                flushParagraph()
                output.append(line)
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()

        // Auto-close any fence still open at end of input. Insert before the
        // trailing empty line if the original input ended with a newline so
        // the closure lands on its own line and the trailing newline stays.
        if let fence = fenceState {
            let closure = String(repeating: fence.marker, count: fence.length)
            if output.last == "" {
                output.insert(closure, at: output.count - 1)
            } else {
                output.append(closure)
            }
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Fence handling

    private struct FenceState {
        let marker: Character
        let length: Int
    }

    private static func fenceOpening(in trimmedLeading: String) -> FenceState? {
        guard let first = trimmedLeading.first, first == "`" || first == "~" else { return nil }
        let length = trimmedLeading.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        return FenceState(marker: first, length: length)
    }

    private static func isClosingFenceLine(_ trimmedLeading: String, active: FenceState) -> Bool {
        guard let first = trimmedLeading.first, first == active.marker else { return false }
        let length = trimmedLeading.prefix(while: { $0 == first }).count
        guard length >= active.length else { return false }
        let rest = trimmedLeading.dropFirst(length)
        return rest.allSatisfy { $0 == " " || $0 == "\t" }
    }
}
