import Foundation

/// Case/width/diacritic normalization plus fzf's character-class lattice.
///
/// Pure and stateless — memoization lives in `FuzzyMatchFieldCache`.
enum FuzzyMatchTextNormalizer {
    /// fzf's 7-way class lattice. Raw values are ordered: boundary tests compare
    /// against `nonWord`.
    enum CharacterClass: UInt8 {
        case white = 0
        case nonWord = 1
        case delimiter = 2
        case lower = 3
        case upper = 4
        case letter = 5
        case number = 6
    }

    /// Length-preserving normalization of one Unicode scalar.
    ///
    /// Returns exactly one scalar for every input scalar. When folding would change
    /// the scalar count (`İ` folds to `i` + U+0307) the original is returned
    /// instead. This invariant is load-bearing: `FuzzyMatchField` keeps five
    /// index-aligned arrays and a length change would desync them.
    static func normalizedScalar(_ scalar: UInt32) -> UInt32 {
        if scalar < 0x80 {
            return (scalar >= 0x41 && scalar <= 0x5A) ? scalar + 0x20 : scalar
        }
        return foldedScalar(scalar)
    }

    /// Classifies a scalar. Always call with the *pre-normalization* scalar so
    /// camelCase boundaries (`opencodeGo`, `cloudflareAIGateway`) survive lowercasing.
    static func characterClass(of scalar: UInt32) -> CharacterClass {
        if scalar < 0x80 {
            switch scalar {
            case 0x61...0x7A: return .lower
            case 0x41...0x5A: return .upper
            case 0x30...0x39: return .number
            case 0x2F, 0x2C, 0x3A, 0x3B, 0x7C: return .delimiter // "/,:;|"
            case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: return .white
            default: return .nonWord
            }
        }

        guard let unicodeScalar = Unicode.Scalar(scalar) else { return .nonWord }
        switch unicodeScalar.properties.generalCategory {
        case .lowercaseLetter:
            return .lower
        case .uppercaseLetter, .titlecaseLetter:
            return .upper
        case .decimalNumber, .letterNumber, .otherNumber:
            return .number
        case .modifierLetter, .otherLetter:
            return .letter
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format:
            return .white
        default:
            return .nonWord
        }
    }

    /// fzf's `bonusFor(prevClass:class:)`.
    static func bonus(previous: CharacterClass, current: CharacterClass) -> Int {
        if current.rawValue > CharacterClass.nonWord.rawValue {
            switch previous {
            case .white: return FuzzyMatchScore.bonusBoundaryWhite
            case .delimiter: return FuzzyMatchScore.bonusBoundaryDelimiter
            case .nonWord: return FuzzyMatchScore.bonusBoundary
            default: break
            }
        }

        if (previous == .lower && current == .upper) || (previous != .number && current == .number) {
            return FuzzyMatchScore.bonusCamel123
        }

        switch current {
        case .nonWord, .delimiter: return FuzzyMatchScore.bonusNonWord
        case .white: return FuzzyMatchScore.bonusBoundaryWhite
        default: return 0
        }
    }

    /// Separators erased by the collapsed tiers, so `gpt4` can reach `gpt-4o`.
    static func isCollapsibleSeparator(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x2D, 0x5F, 0x2E, 0x2F, 0x3A, 0x20: return true // - _ . / : space
        default: return false
        }
    }

    // MARK: - Private

    private static func foldedScalar(_ scalar: UInt32) -> UInt32 {
        guard let unicodeScalar = Unicode.Scalar(scalar) else { return scalar }
        let source = String(unicodeScalar)
        let folded: String
        if isLatinOrFullwidth(scalar) {
            folded = source.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )
        } else {
            folded = source.lowercased()
        }

        let scalars = folded.unicodeScalars
        guard scalars.count == 1, let first = scalars.first else { return scalar }
        return first.value
    }

    /// Diacritic folding is gated to Latin and fullwidth forms on purpose: applied
    /// globally it strips dakuten (が becomes か), which changes the word.
    private static func isLatinOrFullwidth(_ scalar: UInt32) -> Bool {
        (scalar >= 0x00C0 && scalar <= 0x024F) || (scalar >= 0xFF00 && scalar <= 0xFFEF)
    }
}
