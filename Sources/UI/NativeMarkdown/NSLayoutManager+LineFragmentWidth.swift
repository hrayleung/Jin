import AppKit

extension NSLayoutManager {

    /// Widest line-fragment right edge of the text laid out in `container`.
    ///
    /// Per-fragment, NOT the aggregate `usedRect(for:)`: after an explicit
    /// container resize TextKit 1 reports the aggregate's WIDTH as the whole
    /// container width (a 152pt single line measured 9972 against a 10,000pt
    /// probe container), while the per-fragment used rects stay truthful.
    /// Heights are unaffected by the quirk, so only width readers need this.
    func jinWidestLineFragmentRight(in container: NSTextContainer) -> CGFloat {
        let glyphs = glyphRange(for: container)
        var maxRight: CGFloat = 0
        var index = glyphs.location
        while index < NSMaxRange(glyphs) {
            var effective = NSRange(location: index, length: 0)
            let used = lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &effective)
            maxRight = max(maxRight, used.maxX)
            guard NSMaxRange(effective) > index else { break }
            index = NSMaxRange(effective)
        }
        return maxRight
    }
}
