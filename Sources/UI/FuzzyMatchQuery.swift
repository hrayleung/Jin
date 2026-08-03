import Foundation

/// A normalized, tokenized query.
///
/// Build it once per keystroke and reuse it across every candidate — the
/// per-keystroke budget is won here, not in the scorer.
struct FuzzyMatchQuery {
    struct Token {
        let scalars: [UInt32]
        /// `scalars` with collapsible separators removed. Empty when the token was
        /// nothing *but* separators, which is what keeps `"---"` from matching
        /// every hyphenated model ID.
        let collapsed: [UInt32]
        /// Whether the token contains at least one letter or digit. The subsequence
        /// tier refuses punctuation-only tokens outright.
        let hasWordCharacter: Bool
    }

    let raw: String
    let tokens: [Token]

    /// True when the query has more tokens than `maxTokenCount`. Scoring rejects
    /// such a query outright rather than dropping the tail: a dropped token would
    /// impose no constraint, which is how a *longer* query ends up matching *more*.
    let isOverCapacity: Bool

    /// True when no token survived tokenization. Callers **must** short-circuit on
    /// this and return their input untouched — that is what preserves every
    /// empty-query ordering guarantee.
    var isEmpty: Bool { tokens.isEmpty }
    var tokenCount: Int { tokens.count }

    init(_ raw: String) {
        self.raw = raw
        // Split on whitespace *and* newlines: callers pass strings like " \n ".
        // Never split on `-` or `/`, so "gpt-5" stays one token and can still reach
        // the exact and prefix tiers.
        let parts = raw.split(whereSeparator: \.isWhitespace)
        isOverCapacity = parts.count > FuzzyMatchScore.maxTokenCount
        tokens = parts.prefix(FuzzyMatchScore.maxTokenCount).map { Token($0) }
    }
}

private extension FuzzyMatchQuery.Token {
    init(_ text: Substring) {
        var scalars: [UInt32] = []
        var collapsed: [UInt32] = []
        var hasWordCharacter = false

        for original in text.unicodeScalars.prefix(FuzzyMatchScore.maxTokenLength) {
            let value = original.value
            let normalized = FuzzyMatchTextNormalizer.normalizedScalar(value)
            scalars.append(normalized)
            if !FuzzyMatchTextNormalizer.isCollapsibleSeparator(normalized) {
                collapsed.append(normalized)
            }
            switch FuzzyMatchTextNormalizer.characterClass(of: value) {
            case .lower, .upper, .letter, .number: hasWordCharacter = true
            default: break
            }
        }

        self.init(scalars: scalars, collapsed: collapsed, hasWordCharacter: hasWordCharacter)
    }
}
