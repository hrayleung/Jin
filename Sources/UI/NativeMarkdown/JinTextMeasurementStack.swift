import AppKit

/// An isolated TextKit 1 stack used to answer "how tall/wide would this text
/// be at width W?" **without touching any layout manager attached to a live
/// view's text storage**. It owns its own `NSTextStorage`, so nothing about
/// another storage's state can reach it.
///
/// Three callers, all of them cases where no live manager may be used:
///
///  - `AttributedTextBlock.sizeThatFits` measuring a string that has NOT been
///    applied yet (the apply belongs to `updateNSView`; doing it from a layout
///    callback corrupts TextKit);
///  - `CodeLineNumberGutter.size`, whose content is a pure function of the
///    line count and font and needs no live view at all;
///  - `JinMessageTextView`'s mid-edit fallback, for probes that arrive while a
///    storage edit is still fanning out to its managers.
///
/// Off-live-width probes in the steady state do NOT come here — they go to the
/// per-view shadow layout manager, which shares the live storage and therefore
/// costs no copy. This stack copies, so every call site above is a rare one.
///
/// Why it exists at all: SwiftUI probes `sizeThatFits` at several widths (min,
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

    /// The exact string behind `loadedToken`. A token is a cheap SUMMARY
    /// (signature or character hash + length) and is deliberately blind to
    /// attributes: two strings with the same characters but different fonts —
    /// an app font-size change, a theme swap — mint the same token. Verifying
    /// the real string before claiming a hit is what stops the stack from
    /// answering with the previous attributes' height.
    private static var loadedSource: NSAttributedString?

    /// Instrumentation for the scroll-cost benchmark: how many full string
    /// copies (token misses) and how many `ensureLayout` passes this stack has
    /// performed. Copies are the expensive half.
    static var copyCount = 0
    static var layoutCount = 0
    /// Copies attributed to each call site, keyed by the token key's prefix.
    static var copiesByKind: [String: Int] = [:]

    /// Identity of the content loaded into the stack. `key` distinguishes
    /// content sources (a live view, or a not-yet-applied string); `version`
    /// separates successive mutations of the same source.
    struct Token: Equatable {
        let key: String
        let version: UInt64
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

    /// Widest line-fragment right edge at `containerWidth`.
    static func maxLineRight(
        of attributed: @autoclosure () -> NSAttributedString,
        token: Token,
        containerWidth: CGFloat
    ) -> CGFloat {
        prepare(attributed, token: token, containerWidth: containerWidth)
        return ceil(layoutManager.jinWidestLineFragmentRight(in: container))
    }

    /// Unwrapped size (widest line × total height) plus `inset` on both axes —
    /// the natural size of a view that never wraps, e.g. the code gutter.
    static func size(
        of attributed: @autoclosure () -> NSAttributedString,
        token: Token,
        inset: NSSize
    ) -> NSSize {
        prepare(attributed, token: token, containerWidth: 100_000)
        // HEIGHT from the aggregate rect, WIDTH from the per-fragment scan
        // (see `jinWidestLineFragmentRight`): after an explicit container
        // resize TextKit 1 reports the aggregate's width as the whole
        // container (100_000 here).
        return NSSize(
            width: ceil(layoutManager.jinWidestLineFragmentRight(in: container)) + inset.width * 2,
            height: ceil(layoutManager.usedRect(for: container).height) + inset.height * 2
        )
    }

    private static func prepare(
        _ attributed: () -> NSAttributedString,
        token: Token,
        containerWidth: CGFloat
    ) {
        // A token mismatch is a decided miss and skips the string entirely.
        // A token MATCH still has to be verified against the real string: the
        // token is attribute-blind, so a font/theme change collides with the
        // content it replaced and would otherwise be answered from the old
        // layout. The verification is O(1) whenever the caller hands back the
        // same instance (the render pipeline's cached strings do), and never
        // costs a copy or a re-layout on a hit.
        if loadedToken != token {
            load(attributed(), token: token)
        } else {
            let source = attributed()
            if !(loadedSource === source || loadedSource?.isEqual(to: source) == true) {
                load(source, token: token)
            }
        }
        let width = max(1, containerWidth)
        if abs(container.size.width - width) > 0.5 {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        layoutCount += 1
    }

    private static func load(_ source: NSAttributedString, token: Token) {
        // A plain copy: attachments (inline math) are shared by reference and
        // never mutated here.
        storage.setAttributedString(source)
        loadedToken = token
        loadedSource = source
        copyCount += 1
        let kind = String(token.key.prefix(while: { $0 != ":" }))
        copiesByKind[kind, default: 0] += 1
    }
}
