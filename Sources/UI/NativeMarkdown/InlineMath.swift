import AppKit
import SwiftMath

/// Inline math (`$…$` / `\(…\)`) support for the prose path. Splits a text run
/// into prose + math segments and renders each math span natively (SwiftMath →
/// `NSImage` → baseline-aligned `NSTextAttachment`). On a parse failure the span
/// degrades to its raw source text — never a WebView.
///
/// Detection runs on `Markdown.Text` nodes *after* swift-markdown has already
/// split out inline code, so code spans are skipped for free. Currency like
/// `$5` is avoided with pandoc's rule: an opening `$` must be followed by a
/// non-space, and a closing `$` must be preceded by a non-space and not
/// followed by a digit.
enum InlineMath {
    enum Segment: Equatable {
        case text(String)
        /// `inner` is the LaTeX to render; `original` is the full delimited
        /// source to show verbatim if rendering fails.
        case math(inner: String, original: String)
    }

    /// Quick reject so the ~majority of prose runs skip the scan entirely.
    static func mightContainMath(_ s: String) -> Bool {
        s.contains("$") || s.contains("\\(")
    }

    static func split(_ s: String) -> [Segment] {
        guard mightContainMath(s) else { return [.text(s)] }

        let chars = Array(s)
        let n = chars.count
        var segments: [Segment] = []
        var textStart = 0
        var i = 0

        func flushText(upTo end: Int) {
            if end > textStart {
                segments.append(.text(String(chars[textStart..<end])))
            }
        }

        while i < n {
            let c = chars[i]

            if c == "\\", i + 1 < n {
                // \( … \) explicit inline math.
                if chars[i + 1] == "(", let close = findParenClose(chars, from: i + 2) {
                    let inner = String(chars[(i + 2)..<close])
                    if isPlausibleInlineMath(inner) {
                        flushText(upTo: i)
                        segments.append(.math(inner: inner, original: "\\(" + inner + "\\)"))
                        i = close + 2
                        textStart = i
                        continue
                    }
                }
                // Any other backslash escape (incl. \$) — pass both chars through as text.
                i += 2
                continue
            }

            if c == "$" {
                // Opening `$`: needs a following non-space, non-`$`.
                if i + 1 < n, chars[i + 1] != "$", !chars[i + 1].isWhitespace,
                   let close = findDollarClose(chars, from: i + 1) {
                    let inner = String(chars[(i + 1)..<close])
                    if isPlausibleInlineMath(inner) {
                        flushText(upTo: i)
                        segments.append(.math(inner: inner, original: "$" + inner + "$"))
                        i = close + 1
                        textStart = i
                        continue
                    }
                }
                i += 1
                continue
            }

            i += 1
        }

        flushText(upTo: n)
        return segments.isEmpty ? [.text(s)] : segments
    }

    /// LaTeX never legitimately contains CJK ideographs or CJK punctuation
    /// (modulo rare `\text{中文}` — accepted tradeoff), and real inline
    /// formulas are short. Without this, two stray `$` characters around a
    /// CJK ticker list (`$AAPL、$TSLA`) or half a paragraph apart would be
    /// rendered as one garbage math span, swallowing the prose between.
    private static let inlineMathMaxLength = 120

    private static func isPlausibleInlineMath(_ inner: String) -> Bool {
        guard !inner.isEmpty, inner.count <= inlineMathMaxLength else { return false }
        return !inner.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x2E80...0x303E).contains(v)      // CJK radicals + symbols/punctuation
                || v == 0x3000                        // ideographic space
                || (0x3041...0x30FF).contains(v)      // hiragana + katakana
                || (0x3400...0x4DBF).contains(v)      // CJK extension A
                || (0x4E00...0x9FFF).contains(v)      // CJK unified ideographs
                || (0xAC00...0xD7A3).contains(v)      // hangul syllables
                || (0xF900...0xFAFF).contains(v)      // CJK compatibility ideographs
                || (0xFE30...0xFE4F).contains(v)      // CJK compatibility forms
                || (0xFF00...0xFF65).contains(v)      // fullwidth forms + CJK punct
                || (0x20000...0x2FFFD).contains(v)    // CJK extension B+
        }
    }

    /// Finds a valid closing `$` index for math opened at `from`. Skips escaped
    /// `\$`; the close must be preceded by a non-space and not followed by a
    /// digit. The scan is bounded by `inlineMathMaxLength`: a farther close is
    /// guaranteed to be rejected anyway, and bounding here prevents repeated
    /// stray `$` openers from rescanning an entire long paragraph (O(n²)).
    private static func findDollarClose(_ chars: [Character], from: Int) -> Int? {
        let n = chars.count
        var j = from
        while j < n, j - from <= inlineMathMaxLength {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$" {
                if j > from, !chars[j - 1].isWhitespace, (j + 1 >= n || !chars[j + 1].isNumber) {
                    return j
                }
                // Otherwise keep scanning — handles "$5 and $10" without matching.
            }
            j += 1
        }
        return nil
    }

    /// Returns the index of the backslash in the closing `\)`. Like dollar
    /// math, an overlong candidate cannot be rendered, so the scan stops once
    /// the maximum valid inline span length is exceeded.
    private static func findParenClose(_ chars: [Character], from: Int) -> Int? {
        let n = chars.count
        var j = from
        while j < n - 1, j - from <= inlineMathMaxLength {
            if chars[j] == "\\" {
                if chars[j + 1] == ")" { return j }
                j += 2
                continue
            }
            j += 1
        }
        return nil
    }

    // MARK: - Rendering

    private final class Box { let value: NSAttributedString; init(_ v: NSAttributedString) { value = v } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 1024
        // Values carry rendered bitmaps whose size varies ~20× between a
        // short and a max-length span, so bound bytes as well as count;
        // inserts pass the bitmap size as the cost. A miss just re-renders.
        c.totalCostLimit = 12 * 1024 * 1024
        return c
    }()

    /// An attributed string for one inline-math span: a baseline-aligned image
    /// attachment on success, or the raw delimited source on failure. `nil` is
    /// never returned — callers always get something renderable.
    static func attributedString(inner: String, original: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let resolvedColor = resolveForCurrentAppearance(color)
        // Key on `original` (delimiters + inner), not bare `inner`: `$x$` and
        // `\(x\)` share an `inner` but must persist their own delimited source
        // on the attachment, so an inner-only key would hand back whichever
        // spelling rendered first and corrupt the copied/quoted LaTeX.
        let key = "\(font.pointSize)|\(appearanceTag())|\(original)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        let attachment = makeAttachment(inner: inner, original: original, font: font, color: resolvedColor)
        let result = attachment?.string
            ?? NSAttributedString(string: original, attributes: [.font: font, .foregroundColor: color])
        cache.setObject(Box(result), forKey: key, cost: attachment?.bitmapCost ?? original.utf16.count * 2)
        return result
    }

    private static func makeAttachment(
        inner: String,
        original: String,
        font: NSFont,
        color: NSColor
    ) -> (string: NSAttributedString, bitmapCost: Int)? {
        let image = MTMathImage(
            latex: MathRenderer.normalize(inner),
            fontSize: font.pointSize,
            textColor: color,
            labelMode: .text,
            textAlignment: .left
        )
        let (error, nsImage) = image.asImage()
        guard error == nil, let nsImage else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = nsImage
        // The image's internal baseline sits `descent` above its bottom edge;
        // shifting the attachment down by `descent` lands that baseline on the
        // text baseline.
        attachment.bounds = CGRect(
            x: 0,
            y: -image.descent,
            width: nsImage.size.width,
            height: nsImage.size.height
        )
        let string = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        // Carry a font so line metrics around the attachment stay consistent.
        string.addAttribute(.font, value: font, range: NSRange(location: 0, length: string.length))
        // Side-channel the delimited source on the (length-1) attachment glyph
        // so copy/quote can recover the LaTeX the rendered image otherwise
        // erases. Layout-inert; length-preserving (see `jinInlineMathSource`).
        string.addAttribute(.jinInlineMathSource, value: original, range: NSRange(location: 0, length: string.length))
        // `size` is in points; the backing bitmap renders at Retina scale, so
        // account ~2x per axis for the cache's byte budget.
        let bitmapCost = max(1, Int(nsImage.size.width * nsImage.size.height) * 4 * 4)
        return (string, bitmapCost)
    }

    private static func resolveForCurrentAppearance(_ color: NSColor) -> NSColor {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func appearanceTag() -> String {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "d" : "l"
    }
}
