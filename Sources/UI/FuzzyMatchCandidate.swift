import Foundation

/// The full field set of one searchable entity — provider ⊕ model, agent ⊕ its
/// model, and so on.
///
/// Token satisfaction is evaluated **per field**, never against a concatenation.
/// That is what makes cross-entity search safe: joining the fields into one string
/// would let `"opencode"` subsequence-match
/// `"Anthropic anthropic Claude Sonnet claude-sonnet-4-6"` across the seams.
struct FuzzyMatchCandidate {
    let fields: [FuzzyMatchField]

    /// Empty fields are dropped, so callers may pass `?? ""` freely. Duplicates are
    /// *not* removed and do not need to be: a token's score is the `max` over
    /// fields, so a string that appears twice (a provider whose `name` equals its
    /// `typeRaw`, a model whose `name` equals its `id`) is still only paid once.
    init(fields: [FuzzyMatchField]) {
        self.fields = fields.filter { !$0.isEmpty }
    }

    /// Convenience for single-dimension catalogs, where every string is rendered.
    init(strings: [String]) {
        self.init(fields: strings.map { FuzzyMatchFieldCache.shared.field($0) })
    }
}
