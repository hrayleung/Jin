import AppKit

/// Pure helpers for the click-to-copy LaTeX popover.
///
/// Rendered math has no recoverable characters — display blocks are an
/// `MTMathUILabel`, inline spans are a `U+FFFC` attachment — so Copy has to
/// go back to the original delimited source. Hit-testing and click-vs-drag
/// live here (no views, no pasteboard) so the mouse path in
/// `JinMessageTextView` stays a thin adapter and the rules are unit-tested
/// without spinning a run loop.
enum LatexSourceCopy {
    /// Pointer travel still considered a click, not a drag. Tight enough that
    /// a real drag-select does not pop the panel, loose enough for a slightly
    /// unsteady press.
    static let clickSlop: CGFloat = 4

    /// After a transient/semitransient popover consumes a click to close,
    /// the same mouse-up would otherwise reopen it. Same-identity presents
    /// inside this window are suppressed; a different formula is not.
    static let reopenSuppressionWindow: CFTimeInterval = 0.35

    /// Extra points around a math run that still count as a hit. Tall
    /// formulas (fractions, products) overflow the line fragment; a few
    /// points of slop also makes a one-character `$n$` clickable.
    static let glyphHitSlop: CGFloat = 4

    struct Hit: Equatable {
        var charIndex: Int
        var source: String
        var rectInView: CGRect
    }

    struct ClickCandidate: Equatable {
        var charIndex: Int
        var source: String
        var downPointInWindow: NSPoint
        var rectInView: CGRect
    }

    /// Identifies an open popover so a click that just closed it does not
    /// bounce it back open, while a click on a *different* formula still
    /// presents in the same gesture.
    struct PresentationIdentity: Equatable {
        var viewID: ObjectIdentifier
        var charIndex: Int?

        static func of(_ view: NSView, charIndex: Int?) -> PresentationIdentity {
            PresentationIdentity(viewID: ObjectIdentifier(view), charIndex: charIndex)
        }
    }

    struct PopoverLayout: Equatable {
        var size: CGSize
        /// Exact wrap width of the source block, matching the SwiftUI frame
        /// so measurement and drawing cannot disagree and overflow.
        var sourceWidth: CGFloat
        var sourceMaxHeight: CGFloat
        var sourceNeedsScroll: Bool
    }

    /// Pixel chrome of `LatexSourceCopyPopoverView`. Layout and the view must
    /// share these so a short formula never clips and a long one never grows
    /// past the scroll cap.
    enum PopoverChrome {
        static let padding: CGFloat = 12
        static let headerHeight: CGFloat = 22
        static let headerToSource: CGFloat = 8
        static let minOuterWidth: CGFloat = 280
        static let maxOuterWidth: CGFloat = 400
        static let maxSourceHeight: CGFloat = 180
        static let sourceFontSize: CGFloat = 11
        static var sourceFont: NSFont {
            .monospacedSystemFont(ofSize: sourceFontSize, weight: .regular)
        }
    }

    /// Display-math blocks store the inner LaTeX (no delimiters). Wrap it in
    /// `$$…$$` so a round-trip paste re-renders as display math, matching the
    /// context-menu Copy that shipped with the native renderer.
    static func delimitedDisplaySource(_ latex: String) -> String {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        return "$$\n\(trimmed)\n$$"
    }

    static func dragDistanceSquared(from a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// True when the mouse-up should present the copy popover rather than
    /// being treated as the end of a drag-select, a modified click, or a
    /// multi-click (double-click word select).
    ///
    /// Selection length is intentionally ignored: a parse-failure fallback
    /// is many characters, and AppKit selecting that run used to suppress
    /// the popover — the "some formulas click, some only copy" bug.
    static func isClick(
        dragDistanceSquared: CGFloat,
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard clickCount == 1 else { return false }
        guard dragDistanceSquared <= clickSlop * clickSlop else { return false }
        let mods = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowed: NSEvent.ModifierFlags = [.shift, .command, .option, .control]
        return mods.intersection(disallowed).isEmpty
    }

    static func shouldSuppressReopen(
        now: CFAbsoluteTime,
        lastClose: (identity: PresentationIdentity, at: CFAbsoluteTime)?,
        presenting: PresentationIdentity
    ) -> Bool {
        guard let last = lastClose else { return false }
        guard now - last.at < reopenSuppressionWindow else { return false }
        return last.identity == presenting
    }

    static func source(at charIndex: Int, in attributed: NSAttributedString) -> String? {
        guard charIndex >= 0, charIndex < attributed.length else { return nil }
        guard let source = attributed.attribute(
            .jinInlineMathSource,
            at: charIndex,
            effectiveRange: nil
        ) as? String else { return nil }
        return source.isEmpty ? nil : source
    }

    /// Hit-test every math run by its laid-out bounds, not `glyphIndex`.
    ///
    /// `glyphIndex(for:)` only sees the line fragment. A fraction or `\prod`
    /// attachment overflows that fragment, so a click on the visible formula
    /// snapped to neighboring prose and the popover never opened. Enumerating
    /// `.jinInlineMathSource` runs uses the attachment's full rect (and the
    /// whole fallback `$…$` run), which is how KaTeX/ChatGPT treat the
    /// equation as one hit target. Typical paragraphs have a handful of
    /// spans; this is cheaper than a wrong snap.
    static func inlineMathHit(at pointInView: NSPoint, in textView: NSTextView) -> Hit? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else { return nil }
        guard textStorage.length > 0 else { return nil }

        let origin = textView.textContainerOrigin
        let containerPoint = NSPoint(
            x: pointInView.x - origin.x,
            y: pointInView.y - origin.y
        )

        var best: (hit: Hit, area: CGFloat)?
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.jinInlineMathSource, in: full, options: []) { value, range, _ in
            guard let source = value as? String, !source.isEmpty else { return }
            if textStorage.attribute(.link, at: range.location, effectiveRange: nil) != nil {
                return
            }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return }
            let raw = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let padded = raw.insetBy(dx: -glyphHitSlop, dy: -glyphHitSlop)
            guard padded.contains(containerPoint) else { return }
            let viewRect = raw.offsetBy(dx: origin.x, dy: origin.y)
            let hit = Hit(charIndex: range.location, source: source, rectInView: viewRect)
            let area = max(1, raw.width * raw.height)
            if best == nil || area < best!.area {
                best = (hit, area)
            }
        }
        return best?.hit
    }

    static func clickCandidate(event: NSEvent, hit: Hit?) -> ClickCandidate? {
        guard event.clickCount == 1 else { return nil }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowed: NSEvent.ModifierFlags = [.shift, .command, .option, .control]
        guard mods.intersection(disallowed).isEmpty else { return nil }
        guard let hit else { return nil }
        return ClickCandidate(
            charIndex: hit.charIndex,
            source: hit.source,
            downPointInWindow: event.locationInWindow,
            rectInView: hit.rectInView
        )
    }

    /// Intrinsic size of the copy popover. Width tracks a short formula and
    /// clamps a long one; height grows with wrapped source up to a scroll cap
    /// so a giant `align` block cannot produce a screen-filling panel.
    ///
    /// Measurement MUST use `usesLineFragmentOrigin`. `size(withAttributes:)`
    /// is a single-line API: `$$\nformula\n$$` would report one line, the
    /// popover would clip to the opening `$$`, and the user would see `$$...`.
    static func popoverLayout(for source: String) -> PopoverLayout {
        let chrome = PopoverChrome.self
        let horizontalChrome = chrome.padding * 2
        let maxSourceWidth = chrome.maxOuterWidth - horizontalChrome
        let natural = measureSource(source, maxWidth: maxSourceWidth)
        let verticalChrome = chrome.padding * 2 + chrome.headerHeight + chrome.headerToSource
        let outerWidth = min(
            chrome.maxOuterWidth,
            max(chrome.minOuterWidth, natural.width + horizontalChrome)
        )
        // Always wrap to the panel's inner width, not the tight measured
        // line. A 260pt measure inside a 280pt panel was re-wrapping in
        // SwiftUI and splitting `\mu_2 = …` across lines.
        let sourceWidth = max(1, outerWidth - horizontalChrome)
        let fitted = measureSource(source, maxWidth: sourceWidth)
        let sourceHeight = min(chrome.maxSourceHeight, fitted.height)
        let outerHeight = verticalChrome + sourceHeight
        return PopoverLayout(
            size: CGSize(width: ceil(outerWidth), height: ceil(outerHeight)),
            sourceWidth: sourceWidth,
            sourceMaxHeight: sourceHeight,
            sourceNeedsScroll: fitted.height > chrome.maxSourceHeight
        )
    }

    /// Line-fragment bounds of `source` in the popover's monospaced font.
    /// Uses the same `NSFont` the SwiftUI view renders, plus word-wrap, so
    /// the panel width and the drawn glyphs cannot drift.
    static func measureSource(_ source: String, maxWidth: CGFloat) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PopoverChrome.sourceFont,
            .paragraphStyle: paragraph,
        ]
        let ns = source as NSString
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let natural = ns.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: options,
            attributes: attributes
        )
        let naturalWidth = max(1, ceil(natural.width))
        if naturalWidth <= maxWidth {
            return CGSize(width: naturalWidth, height: max(14, ceil(natural.height)))
        }
        let wrapped = ns.boundingRect(
            with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: options,
            attributes: attributes
        )
        return CGSize(width: maxWidth, height: max(14, ceil(wrapped.height)))
    }
}
