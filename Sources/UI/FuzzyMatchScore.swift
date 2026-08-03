import Foundation

/// Scoring constants for `FuzzyMatch`.
///
/// The alignment constants are fzf's defaults verbatim (`src/algo/algo.go`); the
/// tier bases are Jin's. Tiers are spaced 100_000 apart while the in-tier
/// refinement is bounded by roughly 5_800, so a better tier always wins — no
/// amount of alignment polish on a weak match can outrank a stronger one.
enum FuzzyMatchScore {
    // MARK: - fzf alignment constants

    static let scoreMatch = 16
    static let scoreGapStart = -3
    static let scoreGapExtension = -1
    static let bonusBoundary = 8
    static let bonusNonWord = 8
    static let bonusCamel123 = 7
    static let bonusConsecutive = 4
    static let bonusFirstCharMultiplier = 2
    static let bonusBoundaryWhite = 10
    static let bonusBoundaryDelimiter = 9

    // MARK: - Tier bases

    static let tierExact = 1_000_000
    static let tierPrefix = 800_000
    static let tierBoundarySubstring = 600_000
    static let tierSubstring = 500_000
    static let tierCollapsedPrefix = 400_000
    static let tierCollapsedSubstring = 300_000
    static let tierSubsequence = 100_000

    // MARK: - In-tier refinement

    /// Added when the matched field is text the row actually renders. A hit the
    /// user cannot see never outranks an equal-tier hit they can.
    static let prominencePrimary = 4_000

    /// Shorter fields win ties: `max(0, compactnessCap - field.scalars.count)`.
    static let compactnessCap = 64

    /// Multi-token queries whose tokens all land on the same field beat scattered
    /// matches. Deliberately smaller than the tier spacing.
    static let cohesionBonus = 50_000

    // MARK: - Guards

    /// Cost bounds. `maxTokenCount` is enforced fail-closed — a query with more
    /// tokens matches nothing rather than having its tail quietly ignored.
    static let maxTokenLength = 64
    static let maxTokenCount = 16

    /// Kill switch for the subsequence tier. Everything below tier 7 keeps working
    /// with this off; only typo/acronym tolerance is lost.
    static let subsequenceEnabled = true
    static let subsequenceMinTokenLength = 3
    static let subsequenceMaxFieldLength = 64
    static let subsequenceDensityHigh = 0.75
}
