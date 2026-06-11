import Foundation

extension MarkdownRenderPreparation {
    static func preserveInlineCode(
        in line: String,
        transform: (String) -> String
    ) -> String {
        let characters = Array(line)
        guard characters.contains("`") else { return transform(line) }
        // Input that already contains our placeholder scalars would collide
        // with the placeholders we mint — run the transform unprotected
        // instead of risking content duplication on restore.
        guard !MarkdownRepairInvariant.containsPlaceholderScalar(line) else {
            return transform(line)
        }

        var placeholderIndex = 0
        var index = 0
        var sanitized = ""
        var placeholders: [(placeholder: String, content: String)] = []
        sanitized.reserveCapacity(line.count)

        while index < characters.count {
            if characters[index] != "`" {
                sanitized.append(characters[index])
                index += 1
                continue
            }

            let start = index
            var tickCount = 0
            while index < characters.count, characters[index] == "`" {
                tickCount += 1
                index += 1
            }

            var searchIndex = index
            var matchingStart: Int?

            while searchIndex < characters.count {
                if characters[searchIndex] != "`" {
                    searchIndex += 1
                    continue
                }

                var candidateCount = 0
                while searchIndex + candidateCount < characters.count,
                      characters[searchIndex + candidateCount] == "`" {
                    candidateCount += 1
                }

                if candidateCount == tickCount {
                    matchingStart = searchIndex
                    break
                }

                searchIndex += candidateCount
            }

            guard let matchingStart else {
                sanitized.append(contentsOf: String(characters[start..<index]))
                continue
            }

            let matchingEnd = matchingStart + tickCount
            let placeholder = "\u{F0000}JIN_CODE_\(placeholderIndex)\u{F0001}"
            placeholderIndex += 1
            placeholders.append((placeholder, String(characters[start..<matchingEnd])))
            sanitized.append(placeholder)
            index = matchingEnd
        }

        var transformed = transform(sanitized)
        for entry in placeholders {
            transformed = transformed.replacingOccurrences(of: entry.placeholder, with: entry.content)
        }
        // Fail-safe: if a transform corrupted a placeholder, restoration
        // missed it and the line now carries invisible PUA junk in place of
        // the user's code. Return the original line instead — broken
        // styling beats lost code. (The DEBUG stage audits in
        // `repairMarkdown` surface any real transform doing this.)
        if MarkdownRepairInvariant.containsPlaceholderScalar(transformed) {
            return line
        }
        return transformed
    }
}
