import Foundation

/// Fuzzy matching for model, provider, and agent search — an fzf-style scored
/// alignment underneath a literal-match tier ladder.
///
/// The property that matters here is **cross-entity token distribution**: a query
/// like `"opencode luna"` names a provider *and* a model, and each token is allowed
/// to be satisfied by a different field of the same candidate. A candidate matches
/// only when **every** token is satisfied by **some** field, so the AND semantics
/// that keep results tight still hold.
///
/// Two rules keep that from degenerating into a wildcard:
/// - the best field per token is taken with `max`, never summed, so a token that
///   appears in both the provider name and the model ID is only paid for once;
/// - fields are scored separately, never concatenated — a joined string would let a
///   match straddle the seam between two unrelated fields.
enum FuzzyMatch {
    struct Result: Equatable {
        let matched: Bool
        let score: Int

        static let noMatch = Result(matched: false, score: 0)
        /// Empty query: everything matches, nothing ranks.
        static let neutral = Result(matched: true, score: 0)
    }

    /// `.structural` runs the literal tiers only. `.relaxed` also enables the
    /// guarded subsequence tier (typos, acronyms).
    ///
    /// Chooser surfaces that rank by relevance use `.relaxed`; management surfaces
    /// that only filter use `.structural`, so a half-typed query never quietly
    /// widens the list they are editing.
    enum Precision {
        case structural
        case relaxed
    }

    static func score(
        _ query: FuzzyMatchQuery,
        _ candidate: FuzzyMatchCandidate,
        precision: Precision = .relaxed
    ) -> Result {
        guard !query.isEmpty else { return .neutral }
        // A query too long to evaluate fails closed. Truncating it instead would drop
        // tokens before the AND-gate sees them, so a longer query could match more
        // than a shorter one.
        guard !query.isOverCapacity else { return .noMatch }
        let fields = candidate.fields
        guard !fields.isEmpty else { return .noMatch }

        var total = 0
        // Bit i is set while field i has satisfied every token so far.
        var cohesionMask = UInt64.max

        for token in query.tokens {
            var best = -1
            var matchedFields = UInt64.zero

            for (index, field) in fields.enumerated() {
                guard let score = FuzzyMatchFieldScorer.structuralScore(token: token, field: field) else { continue }
                if index < UInt64.bitWidth { matchedFields |= 1 << UInt64(index) }
                if score > best { best = score }
            }

            // The speculative tier is a fallback, not a peer: it only runs when no
            // field matched literally, so it can add rows at the bottom but can
            // never reorder the ones above.
            if best < 0, precision == .relaxed, FuzzyMatchScore.subsequenceEnabled {
                for (index, field) in fields.enumerated() {
                    guard let score = FuzzyMatchFieldScorer.subsequenceScore(token: token, field: field) else { continue }
                    if index < UInt64.bitWidth { matchedFields |= 1 << UInt64(index) }
                    if score > best { best = score }
                }
            }

            guard best >= 0 else { return .noMatch }
            total += best
            cohesionMask &= matchedFields
        }

        // Cohesion means "one field contains the whole query", not "the winning
        // fields happened to coincide". Keying it on the argmax instead would punish
        // a row for matching a token *better* somewhere else: within a provider
        // section every model shares the provider's fields, so the models that
        // matched nothing of their own would collect the bonus and outrank the ones
        // that did.
        if query.tokenCount > 1, cohesionMask != 0 {
            total += FuzzyMatchScore.cohesionBonus
        }

        return Result(matched: true, score: total)
    }

    /// Filter and rank: score descending, then original index ascending.
    ///
    /// An empty query returns `values` untouched — unscored and unsorted.
    static func rank<Value>(
        _ values: [Value],
        query: FuzzyMatchQuery,
        precision: Precision = .relaxed,
        candidate: (Value) -> FuzzyMatchCandidate
    ) -> [Value] {
        rankWithBestScore(values, query: query, precision: precision, candidate: candidate).values
    }

    /// Same as `rank`, but also reports the winning score so a container (a
    /// provider section) can be ranked by its best member.
    static func rankWithBestScore<Value>(
        _ values: [Value],
        query: FuzzyMatchQuery,
        precision: Precision = .relaxed,
        candidate: (Value) -> FuzzyMatchCandidate
    ) -> (values: [Value], bestScore: Int) {
        guard !query.isEmpty else { return (values, 0) }

        var scored: [(index: Int, score: Int)] = []
        scored.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let result = score(query, candidate(value), precision: precision)
            guard result.matched else { continue }
            scored.append((index, result.score))
        }

        // Explicit index tiebreak: `Array.sort` is an unstable introsort, so equal
        // scores would otherwise come back in an arbitrary order between runs.
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
        }

        return (scored.map { values[$0.index] }, scored.first?.score ?? 0)
    }

    /// Filter only — the caller's order is preserved.
    static func filter<Value>(
        _ values: [Value],
        query: FuzzyMatchQuery,
        precision: Precision = .structural,
        candidate: (Value) -> FuzzyMatchCandidate
    ) -> [Value] {
        guard !query.isEmpty else { return values }
        return values.filter { score(query, candidate($0), precision: precision).matched }
    }

    /// Single-string convenience.
    static func match(query: String, target: String, precision: Precision = .relaxed) -> Result {
        score(FuzzyMatchQuery(query), FuzzyMatchCandidate(strings: [target]), precision: precision)
    }
}
