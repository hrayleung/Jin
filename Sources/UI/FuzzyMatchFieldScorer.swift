import Foundation

/// Scores a single query token against a single pre-indexed field.
///
/// The tier ladder, strongest first:
///
/// 1. exact · 2. prefix · 3. boundary substring · 4. substring
/// 5. collapsed prefix · 6. collapsed substring (`gpt4` reaches `gpt-4o`)
/// 7. guarded subsequence (typos and acronyms — `sonet`, `vaig`)
///
/// Tiers 1–6 are *structural*: the token appears literally. Tier 7 is the only
/// speculative one, and it is fenced off behind four preconditions plus a density
/// test — without those it is exactly the garbage generator that made pure
/// subsequence matching unusable here (`codex` matching
/// `accounts/fireworks/models/…`).
enum FuzzyMatchFieldScorer {
    /// Tiers 1–6. `nil` when the token does not literally occur in the field.
    static func structuralScore(token: FuzzyMatchQuery.Token, field: FuzzyMatchField) -> Int? {
        guard !token.scalars.isEmpty, !field.isEmpty else { return nil }

        // Tiers 1–4 always match a contiguous run, so they score straight off a
        // range — no positions array is allocated on the hot path.
        if let tier = literalTier(token: token, field: field) {
            return base(tier: tier.base, field: field)
                + alignmentScore(field: field, range: tier.range)
        }
        if let tier = collapsedTier(token: token, field: field) {
            return base(tier: tier.base, field: field)
                + alignmentScore(field: field, positions: tier.positions)
        }
        return nil
    }

    /// Tier 7. Only consulted when *no* field satisfied the token structurally.
    static func subsequenceScore(token: FuzzyMatchQuery.Token, field: FuzzyMatchField) -> Int? {
        let needle = token.scalars
        // P1: 1–2 character tokens subsequence-match nearly everything.
        guard needle.count >= FuzzyMatchScore.subsequenceMinTokenLength else { return nil }
        // P2: punctuation-only tokens never reach here — this is what pins "---".
        guard token.hasWordCharacter else { return nil }
        // P3: long routing paths are the entire false-positive surface.
        guard field.scalars.count <= FuzzyMatchScore.subsequenceMaxFieldLength else { return nil }
        guard needle.count <= field.scalars.count else { return nil }

        var best: Int?
        for anchor in field.scalars.indices {
            // P4: the alignment must start on a word boundary. This single rule is
            // what keeps "codex" out of "accounts/fireworks/models/minimax-m2".
            guard field.isBoundary[anchor], field.scalars[anchor] == needle[0] else { continue }
            guard let positions = alignedPositions(needle: needle, field: field, anchor: anchor) else { continue }
            guard digitRunsAreAligned(needle: needle, positions: positions, field: field) else { continue }
            guard isAcceptable(positions: positions, field: field, needleCount: needle.count) else { continue }

            let score = base(tier: FuzzyMatchScore.tierSubsequence, field: field)
                + alignmentScore(field: field, positions: positions)
            if score > (best ?? Int.min) { best = score }
        }
        return best
    }

    // MARK: - Tiers

    private static func literalTier(
        token: FuzzyMatchQuery.Token,
        field: FuzzyMatchField
    ) -> (base: Int, range: Range<Int>)? {
        let needle = token.scalars
        let haystack = field.scalars
        guard needle.count <= haystack.count else { return nil }

        if needle == haystack {
            return (FuzzyMatchScore.tierExact, 0..<needle.count)
        }

        var firstIndex: Int?
        var boundaryIndex: Int?
        let head = needle[0]
        for start in 0...(haystack.count - needle.count) {
            // First-character guard: this loop is the innermost thing the picker
            // does per keystroke, and it skips almost every position on one compare.
            guard haystack[start] == head, occurs(needle, in: haystack, at: start) else { continue }
            if firstIndex == nil { firstIndex = start }
            if start == 0 { break }
            if field.isBoundary[start] {
                boundaryIndex = start
                break
            }
        }

        guard let firstIndex else { return nil }
        if firstIndex == 0 {
            return (FuzzyMatchScore.tierPrefix, 0..<needle.count)
        }
        if let boundaryIndex {
            return (
                FuzzyMatchScore.tierBoundarySubstring,
                boundaryIndex..<(boundaryIndex + needle.count)
            )
        }
        return (FuzzyMatchScore.tierSubstring, firstIndex..<(firstIndex + needle.count))
    }

    private static func collapsedTier(
        token: FuzzyMatchQuery.Token,
        field: FuzzyMatchField
    ) -> (base: Int, positions: [Int])? {
        let needle = token.collapsed
        // An all-separator token collapses to nothing; letting it through here
        // would match every field in the catalog.
        guard !needle.isEmpty else { return nil }
        let haystack = field.collapsed
        guard needle.count <= haystack.count else { return nil }

        let head = needle[0]
        for start in 0...(haystack.count - needle.count) {
            guard haystack[start] == head, occurs(needle, in: haystack, at: start) else { continue }
            // Map back into original index space so `4` in "gpt4" is still scored
            // with the boundary bonus it earns after the `-` in "gpt-4o".
            let positions = (start..<(start + needle.count)).map { field.collapsedMap[$0] }
            let base = start == 0
                ? FuzzyMatchScore.tierCollapsedPrefix
                : FuzzyMatchScore.tierCollapsedSubstring
            return (base, positions)
        }
        return nil
    }

    // MARK: - Subsequence alignment

    private static func alignedPositions(
        needle: [UInt32],
        field: FuzzyMatchField,
        anchor: Int
    ) -> [Int]? {
        let scalars = field.scalars
        var positions: [Int] = []
        positions.reserveCapacity(needle.count)

        var pointer = 0
        var index = anchor
        while index < scalars.count, pointer < needle.count {
            if scalars[index] == needle[pointer] {
                positions.append(index)
                pointer += 1
            }
            index += 1
        }
        guard pointer == needle.count, let end = positions.last else { return nil }

        // Re-match right-to-left from the final position to tighten the span, but
        // keep the forward alignment unless the tightened start is still a
        // boundary — the anchor guard is the whole point of this tier.
        var tightened: [Int] = []
        tightened.reserveCapacity(needle.count)
        var backPointer = needle.count - 1
        var backIndex = end
        while backIndex >= anchor, backPointer >= 0 {
            if scalars[backIndex] == needle[backPointer] {
                tightened.append(backIndex)
                backPointer -= 1
            }
            backIndex -= 1
        }
        if backPointer < 0 {
            let ordered = Array(tightened.reversed())
            if let start = ordered.first, field.isBoundary[start] { return ordered }
        }
        return positions
    }

    /// Numbers are not fuzzy. A digit run in the query must line up with a whole
    /// digit run in the field, never a slice of one.
    ///
    /// Without this, "llama 30b" matches "Llama 3.3 70B" (the `3` of `3.3` plus the
    /// `0` of `70`) and "gpt 12b" matches "GPT-OSS 120B" — sizes are exactly the
    /// thing a user is being precise about when they type one.
    private static func digitRunsAreAligned(
        needle: [UInt32],
        positions: [Int],
        field: FuzzyMatchField
    ) -> Bool {
        let scalars = field.scalars
        for index in needle.indices where isDigit(needle[index]) {
            let position = positions[index]

            let continuesBackward = index > 0
                && isDigit(needle[index - 1])
                && positions[index - 1] == position - 1
            if !continuesBackward, position > 0, isDigit(scalars[position - 1]) { return false }

            let continuesForward = index + 1 < needle.count
                && isDigit(needle[index + 1])
                && positions[index + 1] == position + 1
            if !continuesForward, position + 1 < scalars.count, isDigit(scalars[position + 1]) { return false }
        }
        return true
    }

    /// Two ways in, both narrow.
    ///
    /// A middle band ("half the matched characters are on boundaries and the match
    /// is at least half dense") was tried and removed: it is what let "video" reach
    /// `nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B`, because a run of capitals hands
    /// out a boundary per letter. Losing it costs glued queries that skip a whole
    /// word ("gptluna" for "GPT-5.6 Luna"); that is a much better trade than a
    /// picker that answers questions the user did not ask.
    private static func isAcceptable(
        positions: [Int],
        field: FuzzyMatchField,
        needleCount: Int
    ) -> Bool {
        guard let first = positions.first, let last = positions.last else { return false }

        // Deletion typos: "sonet" in "Sonnet" is 0.83, "anthrpic" in "Anthropic" 0.89.
        let density = Double(needleCount) / Double(last - first + 1)
        if density >= FuzzyMatchScore.subsequenceDensityHigh { return true }

        // Pure acronyms at any density: "vaig" over "Vercel AI Gateway" is 0.36.
        let boundaryCount = positions.reduce(into: 0) { $0 += field.isBoundary[$1] ? 1 : 0 }
        return boundaryCount == needleCount
    }

    private static func isDigit(_ scalar: UInt32) -> Bool {
        scalar >= 0x30 && scalar <= 0x39
    }

    // MARK: - Scoring

    private static func base(tier: Int, field: FuzzyMatchField) -> Int {
        tier
            + (field.prominence == .primary ? FuzzyMatchScore.prominencePrimary : 0)
            + max(0, FuzzyMatchScore.compactnessCap - field.scalars.count)
    }

    /// fzf's `calculateScore` for a gapless run: `+16` per matched character, the
    /// first character's boundary bonus doubled, and the rest inheriting the run's
    /// best bonus.
    private static func alignmentScore(field: FuzzyMatchField, range: Range<Int>) -> Int {
        guard let start = range.first else { return 0 }

        var firstBonus = field.bonuses[start]
        var score = FuzzyMatchScore.scoreMatch * range.count
            + firstBonus * FuzzyMatchScore.bonusFirstCharMultiplier

        for index in range.dropFirst() {
            var bonus = field.bonuses[index]
            if bonus >= FuzzyMatchScore.bonusBoundary, bonus > firstBonus { firstBonus = bonus }
            bonus = max(max(bonus, firstBonus), FuzzyMatchScore.bonusConsecutive)
            score += bonus
        }

        return max(0, score)
    }

    /// The general form, for matches with gaps: adds fzf's affine gap penalty and
    /// resets the consecutive-run bonus across each gap.
    private static func alignmentScore(field: FuzzyMatchField, positions: [Int]) -> Int {
        guard let start = positions.first, let end = positions.last else { return 0 }

        var score = 0
        var inGap = false
        var consecutive = 0
        var firstBonus = 0
        var matched = 0

        for index in start...end {
            if matched < positions.count, positions[matched] == index {
                score += FuzzyMatchScore.scoreMatch
                var bonus = field.bonuses[index]
                if consecutive == 0 {
                    firstBonus = bonus
                } else {
                    if bonus >= FuzzyMatchScore.bonusBoundary, bonus > firstBonus { firstBonus = bonus }
                    bonus = max(max(bonus, firstBonus), FuzzyMatchScore.bonusConsecutive)
                }
                score += matched == 0 ? bonus * FuzzyMatchScore.bonusFirstCharMultiplier : bonus
                inGap = false
                consecutive += 1
                matched += 1
            } else {
                score += inGap ? FuzzyMatchScore.scoreGapExtension : FuzzyMatchScore.scoreGapStart
                inGap = true
                consecutive = 0
                firstBonus = 0
            }
        }

        return max(0, score)
    }

    /// Both callers check `needle[0]` themselves, so this resumes at offset 1.
    private static func occurs(_ needle: [UInt32], in haystack: [UInt32], at start: Int) -> Bool {
        for offset in 1..<needle.count where haystack[start + offset] != needle[offset] {
            return false
        }
        return true
    }
}
