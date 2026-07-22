import Foundation

private struct MarkdownInlineCodeTickRun {
    let start: Int
    let end: Int

    var length: Int { end - start }
}

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

        var runs: [MarkdownInlineCodeTickRun] = []
        let escapedPositions = MarkdownInlineTokenizer.escapedPositions(in: characters)
        var index = 0
        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }
            if escapedPositions[index] {
                // Only this backtick is escaped. Any immediately following
                // backticks can still begin their own delimiter run.
                index += 1
                continue
            }
            let start = index
            while index < characters.count, characters[index] == "`" {
                index += 1
            }
            runs.append(MarkdownInlineCodeTickRun(start: start, end: index))
        }

        // Resolve each opener's nearest exact-length closer in one backward
        // pass. Previously every unmatched opener rescanned the rest of the
        // line, turning malformed model output with many differently-sized
        // backtick runs into O(n²) work before swift-markdown even started.
        var nextMatchingRun = Array<Int?>(repeating: nil, count: runs.count)
        var nearestByLength: [Int: Int] = [:]
        for runIndex in runs.indices.reversed() {
            let length = runs[runIndex].length
            nextMatchingRun[runIndex] = nearestByLength[length]
            nearestByLength[length] = runIndex
        }

        var sanitized = ""
        var protectedContents: [String] = []
        sanitized.reserveCapacity(characters.count)
        protectedContents.reserveCapacity(runs.count / 2)

        var cursor = 0
        var runIndex = 0
        while runIndex < runs.count {
            let opener = runs[runIndex]
            guard let closerIndex = nextMatchingRun[runIndex] else {
                runIndex += 1
                continue
            }
            let closer = runs[closerIndex]
            sanitized.append(contentsOf: characters[cursor..<opener.start])
            let placeholderIndex = protectedContents.count
            sanitized.append("\u{F0000}JIN_CODE_\(placeholderIndex)\u{F0001}")
            protectedContents.append(String(characters[opener.start..<closer.end]))
            cursor = closer.end
            // Backtick runs between the pair are literal code content.
            runIndex = closerIndex + 1
        }
        guard !protectedContents.isEmpty else { return transform(line) }
        sanitized.append(contentsOf: characters[cursor..<characters.count])

        // Restore all placeholders in one scan. Repeated
        // `replacingOccurrences` traversed the full transformed line once per
        // inline-code span and became another O(n²) path on generated lists.
        return restoreInlineCodePlaceholders(
            in: transform(sanitized),
            protectedContents: protectedContents
        ) ?? line
    }

    private static func restoreInlineCodePlaceholders(
        in transformed: String,
        protectedContents: [String]
    ) -> String? {
        let characters = Array(transformed)
        let startMarker: Character = "\u{F0000}"
        let endMarker: Character = "\u{F0001}"
        let prefix = "JIN_CODE_"
        var restored = ""
        restored.reserveCapacity(characters.count)
        var restoredIndices = Array(repeating: false, count: protectedContents.count)
        var index = 0

        while index < characters.count {
            if characters[index] == endMarker {
                return nil
            }
            guard characters[index] == startMarker else {
                restored.append(characters[index])
                index += 1
                continue
            }

            var end = index + 1
            while end < characters.count,
                  characters[end] != startMarker,
                  characters[end] != endMarker {
                end += 1
            }
            guard end < characters.count, characters[end] == endMarker else {
                return nil
            }

            let token = String(characters[(index + 1)..<end])
            guard token.hasPrefix(prefix),
                  let placeholderIndex = Int(token.dropFirst(prefix.count)),
                  protectedContents.indices.contains(placeholderIndex) else {
                return nil
            }
            restored.append(protectedContents[placeholderIndex])
            restoredIndices[placeholderIndex] = true
            index = end + 1
        }

        // A transform is allowed to move or duplicate a placeholder, but not
        // delete it: deletion would silently discard the user's code.
        guard restoredIndices.allSatisfy({ $0 }) else { return nil }
        return restored
    }
}
