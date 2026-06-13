import AppKit
import SwiftUI

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

/// `NSHostingView` that forwards vertical-dominant wheel events to the chat
/// timeline via `CodeBlockWheelRouter`. Hosts code-block sub-regions that have
/// no `NSView` of their own (the line-number gutter + its divider) so a wheel
/// over them isn't swallowed by the trapping horizontal scroll view. It only
/// overrides an `NSResponder` event method; intrinsic sizing is identical to a
/// plain `NSHostingView`.
final class WheelForwardingHostingView<Content: View>: NSHostingView<Content> {
    private var wheelRouter = CodeBlockWheelRouter()

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        switch wheelRouter.route(event: event, from: self) {
        case .forwardToTimeline(let timeline):
            timeline.scrollWheel(with: event)
        case .passToSuper:
            super.scrollWheel(with: event)
        }
    }
}

/// Hosts arbitrary SwiftUI content in a `WheelForwardingHostingView`, preserving
/// the content's natural sizing (returns `nil` from `sizeThatFits` so SwiftUI
/// uses the hosting view's intrinsic size). Used to wrap the line-number gutter
/// so vertical scroll over it forwards to the timeline.
struct WheelForwardingContainer<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WheelForwardingHostingView<Content> {
        let host = WheelForwardingHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        return host
    }

    func updateNSView(_ host: WheelForwardingHostingView<Content>, context: Context) {
        host.rootView = content
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WheelForwardingHostingView<Content>,
        context: Context
    ) -> CGSize? {
        // nil → SwiftUI uses the hosting view's intrinsicContentSize, identical
        // to embedding `content` directly. We never impose a width, so nothing
        // about the surrounding layout (or the code's unwrapped height) changes.
        nil
    }
}
