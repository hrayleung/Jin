import Foundation

/// Production-grade fuzzy matching for model search, inspired by fzf/VS Code.
///
/// Instead of pure subsequence matching (which produces garbage like "codex"
/// matching "accounts/fireworks/models/flux..."), this uses a layered strategy:
///
/// 1. **Exact substring** — highest confidence
/// 2. **Separator-collapsed substring** — "gpt4" matches "gpt-4o"
/// 3. **Multi-token AND** — "claude son" requires both tokens present
///
/// Each layer produces a score for ranking; unmatched items are rejected entirely.
enum FuzzyMatch {
    struct Result {
        let matched: Bool
        let score: Int
    }

    static func match(query: String, target: String) -> Result {
        guard !query.isEmpty else {
            return Result(matched: true, score: 0)
        }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        let tokens = queryLower
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if tokens.count > 1 {
            return matchMultiToken(tokens: tokens, target: targetLower)
        }

        return matchSingleToken(query: queryLower, target: targetLower)
    }

    /// Best score across multiple candidate strings (e.g. model name + model ID).
    static func bestMatch(query: String, candidates: [String]) -> Result {
        var best = Result(matched: false, score: 0)
        for candidate in candidates {
            let r = match(query: query, target: candidate)
            if r.matched && r.score > best.score {
                best = r
            }
        }
        return best
    }

    // MARK: - Private

    private static func matchSingleToken(query: String, target: String) -> Result {
        // 1. Exact match
        if query == target {
            return Result(matched: true, score: 10_000)
        }

        // 2. Prefix match
        if target.hasPrefix(query) {
            return Result(matched: true, score: 5_000 + brevityBonus(target))
        }

        // 3. Substring match — bonus when aligned to a word boundary
        if let range = target.range(of: query) {
            let atBoundary = range.lowerBound == target.startIndex
                || isSeparator(target[target.index(before: range.lowerBound)])
            return Result(matched: true, score: (atBoundary ? 3_500 : 3_000) + brevityBonus(target))
        }

        // 4. Separator-collapsed substring ("gpt4" matches "gpt-4o")
        let queryCollapsed = collapseSeparators(query)
        guard !queryCollapsed.isEmpty else { return Result(matched: false, score: 0) }
        let targetCollapsed = collapseSeparators(target)

        if targetCollapsed.contains(queryCollapsed) {
            let atPrefix = targetCollapsed.hasPrefix(queryCollapsed)
            return Result(matched: true, score: (atPrefix ? 2_500 : 2_000) + brevityBonus(targetCollapsed))
        }

        return Result(matched: false, score: 0)
    }

    private static func matchMultiToken(tokens: [String], target: String) -> Result {
        var totalScore = 0
        for token in tokens {
            let r = matchSingleToken(query: token, target: target)
            guard r.matched else { return Result(matched: false, score: 0) }
            totalScore += r.score
        }
        return Result(matched: true, score: totalScore / tokens.count)
    }

    private static func brevityBonus(_ s: String) -> Int {
        max(0, 200 - s.count)
    }

    private static let separatorChars: Set<Character> = ["-", "_", ".", "/", ":", " "]

    private static func isSeparator(_ c: Character) -> Bool {
        separatorChars.contains(c)
    }

    private static func collapseSeparators(_ s: String) -> String {
        String(s.filter { !separatorChars.contains($0) })
    }
}
