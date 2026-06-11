import Foundation

extension MarkdownRenderPreparation {
    private struct FenceDelimiter {
        let marker: Character
        let length: Int
    }

    static func transformOutsideProtectedBlocks(
        in markdown: String,
        transform: (String) -> String
    ) -> String {
        var output = ""
        output.reserveCapacity(markdown.count + 64)

        var activeFenceDelimiter: FenceDelimiter?
        var displayMathDelimiter: MarkdownDisplayMathDelimiters.Delimiter?

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let fenceDelimiter = fenceDelimiter(in: trimmedLeading) {
                if activeFenceDelimiter == nil {
                    activeFenceDelimiter = fenceDelimiter
                } else if isClosingFenceLine(trimmedLeading, for: activeFenceDelimiter!) {
                    activeFenceDelimiter = nil
                }
                output.append(line)
                output.append("\n")
                continue
            }

            if activeFenceDelimiter != nil {
                output.append(line)
                output.append("\n")
                continue
            }

            if let delimiter = displayMathDelimiter {
                output.append(line)
                output.append("\n")
                if case .closes = MarkdownDisplayMathDelimiters.closingRole(
                    ofTrimmedLine: trimmed,
                    delimiter: delimiter
                ) {
                    displayMathDelimiter = nil
                }
                continue
            }

            switch MarkdownDisplayMathDelimiters.openingRole(ofTrimmedLine: trimmed) {
            case .selfContained:
                // `$$x^2$$` — the whole line is LaTeX; shield it from repair.
                output.append(line)
                output.append("\n")
                continue
            case .opens(let delimiter, _):
                // Opener (possibly with seed LaTeX, `$$E=mc^2`) — shield it.
                displayMathDelimiter = delimiter
                output.append(line)
                output.append("\n")
                continue
            case .none:
                break
            }

            if shouldLeaveHTMLLineUntouched(trimmedLeading) {
                output.append(line)
                output.append("\n")
                continue
            }

            output.append(transform(line))
            output.append("\n")
        }

        if !markdown.hasSuffix("\n"), !output.isEmpty {
            output.removeLast()
        }

        return output
    }

    private static func shouldLeaveHTMLLineUntouched(_ trimmedLeading: String) -> Bool {
        guard !trimmedLeading.isEmpty else { return false }
        return trimmedLeading.hasPrefix("<")
            || trimmedLeading.hasPrefix("<!--")
    }

    private static func fenceDelimiter(in trimmedLeading: String) -> FenceDelimiter? {
        guard let marker = trimmedLeading.first, marker == "`" || marker == "~" else {
            return nil
        }

        let length = trimmedLeading.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return FenceDelimiter(marker: marker, length: length)
    }

    private static func isClosingFenceLine(_ trimmedLeading: String, for opening: FenceDelimiter) -> Bool {
        guard let closing = fenceDelimiter(in: trimmedLeading),
              closing.marker == opening.marker,
              closing.length >= opening.length else {
            return false
        }

        let rest = trimmedLeading.dropFirst(closing.length)
        return rest.allSatisfy { $0 == " " || $0 == "\t" }
    }
}
