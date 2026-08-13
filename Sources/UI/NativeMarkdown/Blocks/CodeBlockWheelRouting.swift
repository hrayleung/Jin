import AppKit

/// A code block renders its content inside a SwiftUI `ScrollView(.horizontal)`
/// (so long lines scroll sideways). When the code overflows horizontally, that
/// scroll view's backing `NSScrollView` "owns" the wheel gesture and *consumes*
/// vertical-dominant scroll deltas instead of letting them bubble to the chat
/// timeline — so the page stops scrolling while the pointer sits over a code
/// block. (When the code does NOT overflow there is no horizontal scroll range,
/// the scroll view doesn't claim the gesture, and vertical scroll passes
/// through normally — so only overflowing blocks trap, and there the content
/// fills the width: every hover target is the code text view or the gutter.)
///
/// These helpers intercept `scrollWheel` on the views we own (the code
/// `JinMessageTextView` and the line-number gutter host) and forward
/// vertical-dominant events to the enclosing `ChatTimelineScrollView`. They
/// touch only `NSResponder` event routing — no geometry, no intrinsic sizing —
/// so the code block's measured height (which the recycling table depends on)
/// is unaffected.
struct CodeBlockWheelRouter {
    enum Decision {
        /// Vertical-dominant: hand the (unmodified) event to the timeline so it
        /// scrolls and its unpin hook fires.
        case forwardToTimeline(NSScrollView)
        /// Horizontal-dominant (or no timeline ancestor): let the receiver's
        /// `super` handle it, which scrolls the code's own horizontal view.
        case passToSuper
    }

    private enum Axis { case vertical, horizontal }
    private var latchedAxis: Axis?
    private weak var latchedTimeline: NSScrollView?

    /// Decide routing for `event` originating in `view`. The dominant axis is
    /// latched at gesture start (trackpad `.began`, or each discrete mouse-wheel
    /// tick) and held through `.changed` and the momentum tail, so a curving
    /// flick or a jittery momentum frame can't flip axes mid-scroll. The latch
    /// resets on `.ended`/`.cancelled` so the next gesture re-decides.
    mutating func route(event: NSEvent, from view: NSView) -> Decision {
        // A discrete mouse wheel tick has no gesture envelope (no precise
        // deltas, empty phase + momentumPhase) — decide each tick afresh.
        let isDiscreteTick = !event.hasPreciseScrollingDeltas
            && event.phase == []
            && event.momentumPhase == []
        let isGestureStart = event.phase.contains(.began)

        if isGestureStart || isDiscreteTick || latchedAxis == nil {
            // `scrollingDeltaX/Y` (NOT `deltaX/Y`) unify precise-trackpad and
            // line-based-mouse deltas. Ties favor vertical (page scroll is the
            // common intent over a code block).
            latchedAxis = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? .vertical
                : .horizontal
            latchedTimeline = nil
        }

        defer {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled)
                || event.momentumPhase.contains(.ended)
                || event.momentumPhase.contains(.cancelled) {
                latchedAxis = nil
                latchedTimeline = nil
            }
        }

        guard latchedAxis == .vertical else { return .passToSuper }

        if latchedTimeline == nil {
            latchedTimeline = Self.enclosingTimelineScrollView(from: view)
        }
        if let timeline = latchedTimeline {
            return .forwardToTimeline(timeline)
        }
        return .passToSuper
    }

    /// Walk the *superview* chain to the first `ChatTimelineScrollView`.
    /// Deliberately NOT `enclosingScrollView` (that returns the trapping SwiftUI
    /// horizontal scroll host first) and NOT `nextResponder` bubbling (that
    /// re-enters the same trapping scroll view, which already consumed the
    /// event). The concrete-type match crosses `NSHostingView`/representable
    /// boundaries reliably.
    static func enclosingTimelineScrollView(from view: NSView) -> NSScrollView? {
        var current = view.superview
        while let candidate = current {
            if let timeline = candidate as? ChatTimelineScrollView {
                return timeline
            }
            current = candidate.superview
        }
        return nil
    }
}

/// `NSTextView.hitTest` can return `nil` for in-bounds points that sit in
/// `textContainerInset` (no glyphs). AppKit then reports the SwiftUI
/// horizontal-scroll `DocumentView` behind the text, which is a wheel
/// dead-zone. Both code-block text views claim those pixels themselves.
enum CodeBlockHitTesting {
    /// `point` is in the receiver's **superview** coordinates, matching
    /// `NSView.hitTest(_:)`. Prefer `superHit` (subviews, glyphs) and only
    /// claim the view when AppKit declined an in-bounds point.
    static func hitTest(
        _ view: NSView,
        pointInSuperview point: NSPoint,
        superHit: NSView?
    ) -> NSView? {
        if let superHit { return superHit }
        guard !view.isHidden, view.alphaValue > 0.01 else { return nil }
        let local = view.convert(point, from: view.superview)
        return view.bounds.contains(local) ? view : nil
    }
}
