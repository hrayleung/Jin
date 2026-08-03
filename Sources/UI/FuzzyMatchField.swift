import Foundation

/// One searchable field of one entity, pre-normalized and pre-indexed.
///
/// Build these through `FuzzyMatchFieldCache.shared.field(_:prominence:)` rather
/// than inline in a scoring loop: construction walks the string, scoring against a
/// built field does not.
///
/// A reference type on purpose. A candidate assembles half a dozen of these on every
/// keystroke for every row in the catalog; as a struct holding five arrays, each of
/// those assemblies would retain five buffers instead of one pointer.
final class FuzzyMatchField {
    /// Whether the field's text is actually drawn in the row the user sees.
    enum Prominence: Int {
        /// `model.name`, `provider.name`, `agent.name` — rendered in the row.
        case primary = 0
        /// `model.id`, `provider.typeRaw`, `ProviderType.displayName` — real search
        /// surface, but a hit here has no visible explanation, so it ranks lower.
        case secondary = 1
    }

    let raw: String
    let prominence: Prominence

    /// Normalized scalars. The four arrays below are index-aligned with this one.
    let scalars: [UInt32]
    /// fzf's positional bonus at each index.
    let bonuses: [Int]
    /// Word-boundary flags used by the boundary-substring tier and as the
    /// subsequence tier's anchor guard.
    let isBoundary: [Bool]
    /// `scalars` with collapsible separators removed.
    let collapsed: [UInt32]
    /// Maps a `collapsed` index back into `scalars` index space, so collapsed
    /// matches are still scored against the real boundaries they landed on.
    let collapsedMap: [Int]

    var isEmpty: Bool { scalars.isEmpty }

    init(_ raw: String, prominence: Prominence = .primary) {
        self.raw = raw
        self.prominence = prominence

        let originals = raw.unicodeScalars
        var scalars: [UInt32] = []
        var bonuses: [Int] = []
        var isBoundary: [Bool] = []
        var collapsed: [UInt32] = []
        var collapsedMap: [Int] = []
        scalars.reserveCapacity(originals.count)
        bonuses.reserveCapacity(originals.count)
        isBoundary.reserveCapacity(originals.count)
        collapsed.reserveCapacity(originals.count)
        collapsedMap.reserveCapacity(originals.count)

        var previousClass = FuzzyMatchTextNormalizer.CharacterClass.white
        for original in originals {
            let value = original.value
            let normalized = FuzzyMatchTextNormalizer.normalizedScalar(value)
            let currentClass = FuzzyMatchTextNormalizer.characterClass(of: value)
            let bonus = FuzzyMatchTextNormalizer.bonus(previous: previousClass, current: currentClass)

            if !FuzzyMatchTextNormalizer.isCollapsibleSeparator(normalized) {
                collapsed.append(normalized)
                collapsedMap.append(scalars.count)
            }
            scalars.append(normalized)
            bonuses.append(bonus)
            // Deliberate deviation from fzf: an upper→upper transition scores 0
            // there, which hides the `I` in "Vercel AI Gateway" from acronym
            // matching. Treating uppercase as a boundary is what makes "vaig" work.
            isBoundary.append(bonus >= FuzzyMatchScore.bonusBoundary || currentClass == .upper)
            previousClass = currentClass
        }

        self.scalars = scalars
        self.bonuses = bonuses
        self.isBoundary = isBoundary
        self.collapsed = collapsed
        self.collapsedMap = collapsedMap
    }
}
