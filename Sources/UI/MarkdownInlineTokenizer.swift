import Foundation

enum MarkdownInlineToken: Equatable {
    case inlineCode(Range<String.Index>)
    case emphasis(marker: String, full: Range<String.Index>)
    case unmatchedMarker(marker: String, position: String.Index)
}

struct MarkdownInlineUnmatchedMarker: Equatable {
    let marker: String
    let position: String.Index
}

enum MarkdownInlineTokenizer {
    /// Marks characters escaped by an odd-length run of immediately preceding
    /// backslashes. Backtick scanners share this so protection and tokenization
    /// cannot disagree about whether a code fence is literal.
    static func escapedPositions(in characters: [Character]) -> [Bool] {
        var escaped = Array(repeating: false, count: characters.count)
        var precedingBackslashes = 0
        for offset in characters.indices {
            escaped[offset] = precedingBackslashes % 2 == 1
            if characters[offset] == "\\" {
                precedingBackslashes += 1
            } else {
                precedingBackslashes = 0
            }
        }
        return escaped
    }

    static func tokenize(_ paragraph: String) -> [MarkdownInlineToken] {
        InlineScanner(paragraph: paragraph).scan()
    }

    static func emphasisRanges(in paragraph: String) -> [Range<String.Index>] {
        tokenize(paragraph).compactMap { token in
            switch token {
            case .emphasis(_, let full):
                return full
            case .inlineCode(let range):
                return range
            case .unmatchedMarker:
                return nil
            }
        }
        .sorted { $0.lowerBound < $1.lowerBound }
    }

    static func unmatchedMarkers(in paragraph: String) -> [MarkdownInlineUnmatchedMarker] {
        tokenize(paragraph).compactMap { token -> MarkdownInlineUnmatchedMarker? in
            if case .unmatchedMarker(let marker, let position) = token {
                return MarkdownInlineUnmatchedMarker(marker: marker, position: position)
            }
            return nil
        }
    }
}

private final class InlineScanner {
    private let chars: [Character]
    private let indices: [String.Index]
    /// Whether the character at an offset is escaped by an odd-length run of
    /// backslashes immediately before it. Computing this once avoids walking
    /// backwards from every delimiter in backslash-heavy model output.
    private let escapedPositions: [Bool]

    init(paragraph: String) {
        let charArray = Array(paragraph)
        self.chars = charArray
        self.escapedPositions = MarkdownInlineTokenizer.escapedPositions(in: charArray)

        var idxs: [String.Index] = []
        idxs.reserveCapacity(charArray.count + 1)
        var idx = paragraph.startIndex
        idxs.append(idx)
        while idx != paragraph.endIndex {
            idx = paragraph.index(after: idx)
            idxs.append(idx)
        }
        self.indices = idxs
    }

    func scan() -> [MarkdownInlineToken] {
        var tokens: [MarkdownInlineToken] = []
        let codeRanges = findInlineCodeRanges(into: &tokens)
        var runs = findDelimiterRuns(excluding: codeRanges)

        for marker in DelimiterMarker.all {
            pair(runs: &runs, for: marker, into: &tokens)
        }

        // Only opener-flanking unmatched runs are reported. Closer-only
        // leftovers (e.g. a trailing `*` after a period — `she said.*`)
        // cannot be repaired by appending a closer at end-of-paragraph; doing
        // so would just add more literal asterisks. Leave them as the model
        // emitted them.
        //
        // Operator-shaped asterisk runs are excluded too: `f(x)**2` /
        // `a**b` / `2**8` are exponent notation whose run is left-flanking
        // (so it "can open") but has no closer anywhere — appending one at
        // end-of-paragraph would pair it into a bold span CommonMark itself
        // would never produce, swallowing the literal asterisks.
        for run in runs where run.length > 0 && run.canOpen {
            if run.marker == .asterisk, isLiteralOperatorShaped(run) { continue }
            let unit = run.marker == .tilde ? 2 : 1
            var offset = 0
            while offset + unit <= run.length {
                tokens.append(.unmatchedMarker(
                    marker: String(repeating: run.marker.character, count: unit),
                    position: indices[run.start + offset]
                ))
                offset += unit
            }
        }

        return tokens
    }

    // MARK: - Inline code

    private struct BacktickRun {
        let start: Int
        let end: Int

        var length: Int { end - start }
    }

    private func findInlineCodeRanges(into tokens: inout [MarkdownInlineToken]) -> [Range<Int>] {
        let runs = backtickRuns()
        guard !runs.isEmpty else { return [] }

        // Index the next run of each exact length in one backward pass. The
        // old implementation rescanned the entire suffix for every unmatched
        // opener, making malformed backtick-heavy output quadratic.
        var nextMatchingRun = Array<Int?>(repeating: nil, count: runs.count)
        var nearestByLength: [Int: Int] = [:]
        for runIndex in runs.indices.reversed() {
            let length = runs[runIndex].length
            nextMatchingRun[runIndex] = nearestByLength[length]
            nearestByLength[length] = runIndex
        }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(runs.count / 2)
        var runIndex = 0
        while runIndex < runs.count {
            let opener = runs[runIndex]
            if let closerIndex = nextMatchingRun[runIndex] {
                let closer = runs[closerIndex]
                let range = opener.start..<closer.end
                ranges.append(range)
                tokens.append(.inlineCode(indices[range.lowerBound]..<indices[range.upperBound]))
                // Runs inside the code span are content, even when one happens
                // to share the opener's length.
                runIndex = closerIndex + 1
            } else {
                runIndex += 1
            }
        }
        return ranges
    }

    private func backtickRuns() -> [BacktickRun] {
        var result: [BacktickRun] = []
        var pos = 0
        while pos < chars.count {
            guard chars[pos] == "`" else {
                pos += 1
                continue
            }
            if escapedPositions[pos] {
                // Only the first scalar is escaped. In `\``` the remaining
                // two backticks are still a valid two-character run.
                pos += 1
                continue
            }
            let end = pos + sameCharRunLength(at: pos)
            result.append(BacktickRun(start: pos, end: end))
            pos = end
        }
        return result
    }

    // MARK: - Delimiter runs

    private enum DelimiterMarker: Equatable {
        case asterisk
        case underscore
        case tilde

        static let all: [DelimiterMarker] = [.asterisk, .underscore, .tilde]

        init?(_ character: Character) {
            switch character {
            case "*": self = .asterisk
            case "_": self = .underscore
            case "~": self = .tilde
            default: return nil
            }
        }

        var character: Character {
            switch self {
            case .asterisk: return "*"
            case .underscore: return "_"
            case .tilde: return "~"
            }
        }

        var unitLength: Int {
            self == .tilde ? 2 : 1
        }
    }

    private struct Run {
        let marker: DelimiterMarker
        var start: Int
        var length: Int
        let canOpen: Bool
        let canClose: Bool
    }

    private func findDelimiterRuns(excluding codeRanges: [Range<Int>]) -> [Run] {
        var result: [Run] = []
        var pos = 0
        var codeRangeIndex = 0
        while pos < chars.count {
            while codeRangeIndex < codeRanges.count,
                  codeRanges[codeRangeIndex].upperBound <= pos {
                codeRangeIndex += 1
            }
            if codeRangeIndex < codeRanges.count,
               codeRanges[codeRangeIndex].contains(pos) {
                pos = codeRanges[codeRangeIndex].upperBound
                continue
            }
            guard let marker = DelimiterMarker(chars[pos]) else {
                pos += 1
                continue
            }
            if escapedPositions[pos] {
                pos += 1
                continue
            }

            let runStart = pos
            let runLen = sameCharRunLength(at: pos)
            let runEnd = runStart + runLen

            // For ~, only ~~ pairs form strikethrough; pad to even count.
            let usableLen: Int
            if marker == .tilde {
                usableLen = runLen - (runLen % 2)
            } else {
                usableLen = runLen
            }

            if usableLen >= marker.unitLength {
                let prevChar = runStart > 0 ? chars[runStart - 1] : nil
                let nextChar = runStart + usableLen < chars.count ? chars[runStart + usableLen] : nil
                let (canOpen, canClose) = flanking(
                    marker: marker,
                    prevChar: prevChar,
                    nextChar: nextChar
                )
                if canOpen || canClose {
                    result.append(Run(
                        marker: marker,
                        start: runStart,
                        length: usableLen,
                        canOpen: canOpen,
                        canClose: canClose
                    ))
                }
            }

            pos = runEnd
        }
        return result
    }

    // MARK: - Pairing (CommonMark §6.2 + rule of 3)

    private func pair(
        runs: inout [Run],
        for marker: DelimiterMarker,
        into tokens: inout [MarkdownInlineToken]
    ) {
        var stack: [Int] = []  // indices into runs that have this marker

        for i in runs.indices where runs[i].marker == marker {
            // Try to close as many openers as possible.
            while runs[i].length >= marker.unitLength,
                  runs[i].canClose,
                  !stack.isEmpty {
                let topIdx = stack.last!
                if runs[topIdx].length < marker.unitLength {
                    stack.removeLast()
                    continue
                }
                if shouldSkipRuleOfThree(opener: runs[topIdx], closer: runs[i]) {
                    break
                }

                let consumeUnits = min(runs[topIdx].length, runs[i].length) >= 2 * marker.unitLength
                    ? 2 * marker.unitLength
                    : marker.unitLength

                let consume = min(consumeUnits, runs[topIdx].length, runs[i].length)
                let openerStart = runs[topIdx].start + runs[topIdx].length - consume
                let closerEnd = runs[i].start + consume
                let markerStr = String(repeating: marker.character, count: consume)

                tokens.append(.emphasis(
                    marker: markerStr,
                    full: indices[openerStart]..<indices[closerEnd]
                ))

                runs[topIdx].length -= consume
                runs[i].length -= consume
                runs[i].start += consume

                if runs[topIdx].length < marker.unitLength {
                    stack.removeLast()
                }
                if runs[i].length < marker.unitLength {
                    break
                }
            }

            if runs[i].length >= marker.unitLength, runs[i].canOpen {
                stack.append(i)
            }
        }
    }

    /// The Python/maths power-operator shape: `f(x)**2`, `x**2`, `2**8`,
    /// `arr[i]**2`. Requires a digit after the run, or a closing bracket
    /// before it — plain `Foo**Bar` does NOT match because that's the
    /// glued-bold-title pattern completion exists to close (`## Foo**Bar
    /// Baz` at a stream tail). CJK neighbours never match either:
    /// `他说**这很重要` is a glued opener that completion should close.
    private func isLiteralOperatorShaped(_ run: Run) -> Bool {
        guard run.start > 0, run.start + run.length < chars.count else { return false }
        let prev = chars[run.start - 1]
        let next = chars[run.start + run.length]
        let prevIsBracket = prev == ")" || prev == "]"
        let prevIsWord = prev.isASCII && (prev.isLetter || prev.isNumber)
        let nextIsDigit = next.isASCII && next.isNumber
        let nextIsWord = next.isASCII && (next.isLetter || next.isNumber)
        return (prevIsBracket && nextIsWord) || (prevIsWord && nextIsDigit)
    }

    private func shouldSkipRuleOfThree(opener: Run, closer: Run) -> Bool {
        // Per CommonMark §6.2: if one of the two runs is both left-flanking and
        // right-flanking, and the sum of the lengths is divisible by 3 but neither
        // length is divisible by 3, do not pair.
        let isMixedFlanking = (opener.canOpen && opener.canClose) || (closer.canOpen && closer.canClose)
        guard isMixedFlanking else { return false }

        let sumDivisible = (opener.length + closer.length) % 3 == 0
        guard sumDivisible else { return false }

        let bothDivisible = opener.length % 3 == 0 && closer.length % 3 == 0
        return !bothDivisible
    }

    // MARK: - Flanking classification

    private func flanking(
        marker: DelimiterMarker,
        prevChar: Character?,
        nextChar: Character?
    ) -> (canOpen: Bool, canClose: Bool) {
        let prevIsWS = prevChar.map(isUnicodeWhitespace) ?? true
        let prevIsPunct = prevChar.map(isUnicodePunctuation) ?? true
        let nextIsWS = nextChar.map(isUnicodeWhitespace) ?? true
        let nextIsPunct = nextChar.map(isUnicodePunctuation) ?? true

        let leftFlanking = !nextIsWS && (!nextIsPunct || prevIsWS || prevIsPunct)
        let rightFlanking = !prevIsWS && (!prevIsPunct || nextIsWS || nextIsPunct)

        switch marker {
        case .asterisk, .tilde:
            return (leftFlanking, rightFlanking)
        case .underscore:
            // Underscore: cannot open inside a word, cannot close inside a word.
            let canOpen = leftFlanking && (!rightFlanking || prevIsPunct)
            let canClose = rightFlanking && (!leftFlanking || nextIsPunct)
            return (canOpen, canClose)
        }
    }

    // MARK: - Character classification

    private func isUnicodeWhitespace(_ c: Character) -> Bool {
        if c.isWhitespace || c.isNewline { return true }
        if c == "\t" { return true }
        return false
    }

    private func isUnicodePunctuation(_ c: Character) -> Bool {
        // CommonMark: ASCII punctuation OR Unicode general category Pc/Pd/Pe/Pf/Pi/Po/Ps.
        if c.isPunctuation { return true }
        if c.isASCII, let scalar = c.unicodeScalars.first {
            let v = scalar.value
            // ASCII punctuation ranges: !"#$%&'()*+,-./ :;<=>?@ [\]^_` {|}~
            if (0x21...0x2F).contains(v) { return true }
            if (0x3A...0x40).contains(v) { return true }
            if (0x5B...0x60).contains(v) { return true }
            if (0x7B...0x7E).contains(v) { return true }
        }
        return false
    }

    // MARK: - Low-level helpers

    private func sameCharRunLength(at pos: Int) -> Int {
        let ch = chars[pos]
        var len = 0
        while pos + len < chars.count, chars[pos + len] == ch {
            len += 1
        }
        return len
    }

}
