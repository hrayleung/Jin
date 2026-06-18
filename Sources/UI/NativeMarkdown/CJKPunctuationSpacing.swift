import AppKit
import CoreText
import os

/// Trims the half-em of blank space that fullwidth CJK brackets (（）【】「」…)
/// carry on their open side, so they render snug against neighbouring content
/// instead of floating with a visible gap.
///
/// **Why this exists.** A fullwidth bracket occupies a full em (e.g. 14pt at
/// body size) but its ink lives in only ~3pt on one side — the other ~10pt is
/// blank. The old WKWebView chat renderer got WebKit's default
/// `text-spacing-trim`, which trims that blank at line boundaries and around
/// mixed-script content; the native TextKit-1 renderer (#353) applies no CJK
/// punctuation spacing, so the blank shows — most jarringly as a gap to the
/// LEFT of an opening bracket, and as a stranded bracket pushed ~10pt off the
/// margin when it wraps to the start of a line. The defect only reproduces
/// when the locale's CJK fallback is PingFang SC (Chinese), which renders
/// these glyphs full-width; Hiragino (Japanese) already draws them tight.
///
/// **The fix.** Reassign each fullwidth-bracket character to its *actual*
/// fallback font (resolved with `CTFontCreateForString`, so we stay consistent
/// with what layout would pick) carrying the AAT `kTextSpacingType` /
/// `kHalfWidthTextSelector` feature. AAT half-width metrics are honoured by
/// `NSLayoutManager` — unlike the OpenType `halt`/`palt` features, which only
/// take effect under CoreText/CTLine shaping and are silently ignored by
/// TextKit 1. The substitution is length-preserving and touches only `.font`,
/// so the underlying characters, plain-text mirror, and selection/highlight
/// offsets are all unchanged (copying still yields the original fullwidth
/// bracket).
enum CJKPunctuationSpacing {
    /// AAT feature type 22 (`kTextSpacingType`) selector 2 (`kHalfWidthTextSelector`).
    /// Spelled as literals because the SFNT layout constants aren't surfaced
    /// to Swift; verified empirically (selector 2 → half-width, selector 0 →
    /// fully proportional) against a real `NSLayoutManager`.
    private static let textSpacingType = 22
    private static let halfWidthSelector = 2

    /// Fullwidth CJK brackets — the glyphs whose open side carries the half-em
    /// blank. Sentence punctuation (。，、：；！？) is intentionally excluded:
    /// its blank is trailing and reads as normal spacing, and the reported
    /// defect was specifically the brackets ("左边的括号").
    private static let bracketUnits: Set<unichar> = [
        0xFF08, 0xFF09,  // （ ）  fullwidth parenthesis
        0xFF3B, 0xFF3D,  // ［ ］  fullwidth square bracket
        0xFF5B, 0xFF5D,  // ｛ ｝  fullwidth curly bracket
        0x3008, 0x3009,  // 〈 〉  angle bracket
        0x300A, 0x300B,  // 《 》  double angle bracket
        0x300C, 0x300D,  // 「 」  corner bracket
        0x300E, 0x300F,  // 『 』  white corner bracket
        0x3010, 0x3011,  // 【 】  lenticular bracket
        0x3014, 0x3015,  // 〔 〕  tortoise-shell bracket
        0x3016, 0x3017,  // 〖 〗  white lenticular bracket
        0x3018, 0x3019,  // 〘 〙  white tortoise-shell bracket
        0x301A, 0x301B,  // 〚 〛  white square bracket
    ]

    /// Reassign every fullwidth-bracket character in `attributed` to a
    /// half-width-metrics variant of its render font. No-op when the string
    /// contains no such brackets (the common case), so the scan is cheap
    /// enough to run on every prose block at build time. Idempotent: a bracket
    /// whose font already carries the half-width feature is skipped, so it is
    /// safe to run more than once over the same range (the inline renderer and
    /// the prose-group folder both run it).
    static func apply(to attributed: NSMutableAttributedString) {
        let ns = attributed.string as NSString
        let length = ns.length
        guard length > 0 else { return }

        var index = 0
        while index < length {
            let unit = ns.character(at: index)
            if bracketUnits.contains(unit),
               // Leave inline code untouched — monospace code should keep its
               // literal fullwidth metrics.
               attributed.attribute(.jinInlineCodeBackground, at: index, effectiveRange: nil) == nil,
               let base = attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont,
               !hasHalfWidthFeature(base) {
                let variant = halfWidthVariant(forBracketUnit: unit, base: base)
                attributed.addAttribute(.font, value: variant, range: NSRange(location: index, length: 1))
            }
            index += 1
        }
    }

    /// Convenience for the raw-`NSAttributedString` producers that build text
    /// outside the inline renderer (plain-text / native-text message bodies,
    /// long-streaming tails, reasoning blocks). Returns the input untouched —
    /// no copy — when it has no fullwidth brackets.
    static func applied(to attributed: NSAttributedString) -> NSAttributedString {
        guard containsBracket(attributed.string) else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        apply(to: mutable)
        return mutable
    }

    private static func containsBracket(_ string: String) -> Bool {
        for unit in string.utf16 where bracketUnits.contains(unit) {
            return true
        }
        return false
    }

    private static func hasHalfWidthFeature(_ font: NSFont) -> Bool {
        guard let settings = font.fontDescriptor.fontAttributes[.featureSettings]
            as? [[NSFontDescriptor.FeatureKey: Any]] else { return false }
        // Match both type and selector: a `kTextSpacingType` feature carrying a
        // different selector (e.g. proportional) is not the half-width variant
        // we apply, so it must not short-circuit the compression.
        return settings.contains {
            ($0[.typeIdentifier] as? Int) == textSpacingType
                && ($0[.selectorIdentifier] as? Int) == halfWidthSelector
        }
    }

    // MARK: - Font resolution (cached)

    private struct CacheKey: Hashable {
        let unit: unichar
        let fontName: String
        let pointSize: CGFloat
    }
    private struct FontBox: @unchecked Sendable { let font: NSFont }
    private static let cache = OSAllocatedUnfairLock<[CacheKey: FontBox]>(initialState: [:])

    private static func halfWidthVariant(forBracketUnit unit: unichar, base: NSFont) -> NSFont {
        let key = CacheKey(unit: unit, fontName: base.fontName, pointSize: base.pointSize)
        return cache.withLock { store in
            if let cached = store[key] { return cached.font }
            // Resolve the font layout would actually use for this glyph (the
            // base font is usually SF, which has no CJK brackets), then add the
            // half-width feature to THAT font — feature settings do not survive
            // automatic fallback, so they must live on the glyph's real font.
            let scalarString = String(utf16CodeUnits: [unit], count: 1) as NSString
            let renderFont = CTFontCreateForString(
                base as CTFont,
                scalarString,
                CFRange(location: 0, length: scalarString.length)
            ) as NSFont
            let descriptor = renderFont.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    NSFontDescriptor.FeatureKey.typeIdentifier: textSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: halfWidthSelector,
                ]],
            ])
            let variant = NSFont(descriptor: descriptor, size: renderFont.pointSize) ?? renderFont
            store[key] = FontBox(font: variant)
            return variant
        }
    }
}
