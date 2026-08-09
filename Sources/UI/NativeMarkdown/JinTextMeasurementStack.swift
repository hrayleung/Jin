import AppKit

/// An isolated TextKit 1 stack used to answer "how tall/wide would this text
/// be at width W?" **without touching the live view's layout manager**.
///
/// Why this exists: SwiftUI probes `sizeThatFits` at several widths (min,
/// ideal, max) per layout pass, and those probes run INSIDE AppKit's layout /
/// constraint cycle. Answering them by resizing the live `NSTextContainer`
/// invalidates the live layout manager mid-cycle; when AppKit then asks the
/// same view for `intrinsicContentSize` later in that cycle, the layout
/// manager fills a layout hole against bookkeeping that no longer matches the
/// storage and throws `-[NSRLEArray objectAtRunIndex:length:]` out of bounds —
/// a hard crash whose only app frame is
/// `computeHeight(forWidth:)` → `NSLayoutManager.ensureLayout`. Measuring on a
/// stack nobody renders from removes the shared mutable state entirely.
///
/// The stack is built exactly like `JinMessageTextView`'s own (same
/// `JinMarkdownLayoutManager` subclass, so its line-breaking delegate applies;
/// `lineFragmentPadding = 0`), so a measurement here wraps identically to the
/// live view — which `JinTextMeasurementParityTests` pins.
@MainActor
enum JinTextMeasurementStack {

    private static let storage: NSTextStorage = {
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        return storage
    }()

    private static let layoutManager = JinMarkdownLayoutManager()

    private static let container: NSTextContainer = {
        let container = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        // Not attached to a view: nothing may drive the width but us.
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        return container
    }()

    /// Identity of the content currently loaded, so repeated probes of the
    /// same content at different widths skip the copy.
    private static var loadedToken: Token?

    /// Identity of the content loaded into the stack. `key` distinguishes
    /// content sources (a live view, or a not-yet-applied string); `version`
    /// separates successive mutations of the same source.
    struct Token: Equatable {
        let key: String
        let version: UInt64

        init(key: String, version: UInt64) {
            self.key = key
            self.version = version
        }

        init(owner: ObjectIdentifier, version: UInt64) {
            self.init(key: "view:\(owner.hashValue)", version: version)
        }
    }

    /// Lays `attributed` out at `containerWidth` and returns the used height.
    static func height(
        of attributed: @autoclosure () -> NSAttributedString,
        token: Token,
        containerWidth: CGFloat
    ) -> CGFloat {
        prepare(attributed, token: token, containerWidth: containerWidth)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    /// Widest line-fragment right edge at `containerWidth`. Per-fragment, not
    /// the aggregate `usedRect`: after an explicit container resize TextKit 1
    /// reports the aggregate WIDTH as the full container width (a 152pt single
    /// line measured 9972), while per-fragment used rects stay truthful.
    static func maxLineRight(
        of attributed: @autoclosure () -> NSAttributedString,
        token: Token,
        containerWidth: CGFloat
    ) -> CGFloat {
        prepare(attributed, token: token, containerWidth: containerWidth)
        return ceil(widestLineRight())
    }

    /// Widest line-fragment right edge of the currently laid-out content.
    private static func widestLineRight() -> CGFloat {
        let glyphs = layoutManager.glyphRange(for: container)
        var maxRight: CGFloat = 0
        var index = glyphs.location
        while index < NSMaxRange(glyphs) {
            var effective = NSRange(location: index, length: 0)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &effective)
            maxRight = max(maxRight, used.maxX)
            guard NSMaxRange(effective) > index else { break }
            index = NSMaxRange(effective)
        }
        return maxRight
    }

    /// Unwrapped size (widest line × total height) plus `inset` on both axes —
    /// the natural size of a view that never wraps, e.g. the code gutter.
    static func size(
        of attributed: @autoclosure () -> NSAttributedString,
        token: Token,
        inset: NSSize
    ) -> NSSize {
        prepare(attributed, token: token, containerWidth: 100_000)
        // HEIGHT from the aggregate rect, WIDTH from the per-fragment scan:
        // after an explicit container resize TextKit 1 reports the aggregate's
        // width as the whole container (100_000 here), while the per-fragment
        // used rects stay truthful.
        return NSSize(
            width: ceil(widestLineRight()) + inset.width * 2,
            height: ceil(layoutManager.usedRect(for: container).height) + inset.height * 2
        )
    }

    private static func prepare(
        _ attributed: () -> NSAttributedString,
        token: Token,
        containerWidth: CGFloat
    ) {
        if loadedToken != token {
            // A plain copy: attachments (inline math) are shared by reference
            // and never mutated here.
            storage.setAttributedString(attributed())
            loadedToken = token
        }
        let width = max(1, containerWidth)
        if abs(container.size.width - width) > 0.5 {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
    }

    /// Drops the loaded content so a later probe re-copies. Called when a view
    /// whose content is currently loaded mutates its storage — the token would
    /// otherwise still match while the bytes differ.
    static func invalidate(owner: ObjectIdentifier) {
        if loadedToken?.key == "view:\(owner.hashValue)" { loadedToken = nil }
    }
}
