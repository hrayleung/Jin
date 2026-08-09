import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// The chat must keep scrolling while the pointer sits over a code block.
///
/// A code block's content lives in a SwiftUI `ScrollView(.horizontal)`, whose
/// backing `NSScrollView` consumes vertical-dominant wheel deltas once it has
/// any horizontal scroll range. Only the views we own forward those deltas to
/// the timeline (`JinMessageTextView`, `CodeLineNumberTextView`), so ANY pixel
/// of the block that hit-tests to something else — the scroll view itself, a
/// SwiftUI backing view, a clip view — is a dead zone where the page freezes.
///
/// The invariant is behavioural, not structural: hitting a view that does not
/// itself forward is fine as long as the event still bubbles to the timeline,
/// so every point is checked by actually scrolling from it.
///
/// NOTE: these dispatch straight to the hit view. Synthesized scroll events
/// carry no window target in a test process, so AppKit's own routing — where a
/// nested scroll view can CLAIM a gesture before any override runs — cannot be
/// exercised here. A green run does not prove the product is fine; only a real
/// hover does.
@MainActor
final class CodeBlockWheelTargetTests: XCTestCase {

    private let blockWidth: CGFloat = 700

    /// Long lines so the block genuinely overflows horizontally — the only
    /// case where the inner scroll view claims the gesture.
    private static let overflowingSource = """
    func performHeightAudit(reason: String, tableView: NSTableView, rows: [ChatTimelineRow]) -> IndexSet {
        tableView.enumerateAvailableRowViews { rowView, row in print("a very long trailing comment to force horizontal overflow") }
        return IndexSet()
    }
    """

    private static let shortSource = "let x = 1\nlet y = 2\n"

    private func realize(source: String, showLineNumbers: Bool) -> (ChatTimelineScrollView, NSView) {
        UserDefaults.standard.set(showLineNumbers, forKey: AppPreferenceKeys.codeBlockShowLineNumbers)
        let timeline = ChatTimelineScrollView(
            frame: NSRect(x: 0, y: 0, width: blockWidth, height: 600)
        )
        let host = NSHostingView(
            rootView: AnyView(
                CodeBlockView(language: "swift", source: source, isStreamingTail: false)
                    .frame(width: blockWidth)
            )
        )
        // Size the block to its CONTENT, like the timeline does. Forcing a
        // taller frame leaves empty SwiftUI container below the code, and
        // sampling that would measure the harness, not the product.
        host.frame = NSRect(x: 0, y: 0, width: blockWidth, height: 10)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(x: 0, y: 0, width: blockWidth, height: ceil(host.fittingSize.height))
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: blockWidth, height: 600))
        document.addSubview(host)
        timeline.documentView = document

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: blockWidth, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = timeline
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            timeline.layoutSubtreeIfNeeded()
        }
        return (timeline, host)
    }

    private final class FlippedDocument: NSView {
        override var isFlipped: Bool { true }
    }

    /// Walks up from `view`: does a wheel-forwarding view come before the
    /// trapping horizontal scroll view?
    private func routing(from view: NSView, timeline: ChatTimelineScrollView) -> String {
        var current: NSView? = view
        while let candidate = current, candidate !== timeline {
            if candidate is JinMessageTextView { return "forwards(code)" }
            if candidate is CodeLineNumberTextView { return "forwards(gutter)" }
            if let scrollView = candidate as? NSScrollView, scrollView !== timeline {
                let range = scrollView.documentView?.frame.width ?? 0
                let visible = scrollView.contentView.bounds.width
                return range > visible + 1 ? "TRAPPED(\(type(of: candidate)))" : "inertScrollView"
            }
            current = candidate.superview
        }
        return "reachesTimeline"
    }

    private func sampleGrid(source: String, showLineNumbers: Bool, label: String) -> [String: Int] {
        let (timeline, host) = realize(source: source, showLineNumbers: showLineNumbers)
        var tally: [String: Int] = [:]
        let bounds = host.bounds
        var samples: [(NSPoint, String)] = []
        let columns = 14
        let rows = 10
        for column in 0..<columns {
            for row in 0..<rows {
                let point = NSPoint(
                    x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / CGFloat(columns),
                    y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                )
                // `hitTest` takes a point in the RECEIVER'S SUPERVIEW space;
                // go through window coordinates so no flipped/scrolled
                // ancestor can skew the sample.
                let inWindow = host.convert(point, to: nil)
                guard let hit = timeline.hitTest(inWindow) else {
                    tally["noHit", default: 0] += 1
                    continue
                }
                let verdict = routing(from: hit, timeline: timeline)
                tally[verdict, default: 0] += 1
                samples.append((point, "\(verdict) <- \(type(of: hit))"))
            }
        }
        print("[wheel-target:\(label)] \(tally)")
        for (point, description) in samples where description.hasPrefix("TRAPPED") {
            print("  dead zone at \(Int(point.x)),\(Int(point.y)): \(description)")
        }
        return tally
    }

    /// Hit-testing to a forwarder is necessary but not sufficient: the
    /// forwarded event has to actually move the timeline. AppKit decides which
    /// scroll view owns a gesture, so a `.changed` event handed to a scroll
    /// view that never saw `.began` can be dropped.
    func testScrollWheelOverCodeActuallyScrollsTheTimeline() throws {
        let (timeline, host) = realize(source: Self.overflowingSource, showLineNumbers: true)
        // Make the timeline scrollable.
        timeline.documentView?.setFrameSize(NSSize(width: blockWidth, height: 4_000))
        timeline.layoutSubtreeIfNeeded()

        guard let codeView = firstView(ofType: JinMessageTextView.self, in: host) else {
            return XCTFail("no code text view realized")
        }

        var forwarded = 0
        timeline.onUserScrollWheel = { _ in forwarded += 1 }

        let before = timeline.contentView.bounds.origin.y
        for _ in 0..<3 {
            guard let event = Self.verticalScrollEvent(deltaY: -3, window: timeline.window) else {
                throw XCTSkip("cannot synthesize scroll events in this environment")
            }
            codeView.scrollWheel(with: event)
            // AppKit applies wheel scrolling through its own animation /
            // display machinery — give the run loop a chance to land it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let after = timeline.contentView.bounds.origin.y
        var router = CodeBlockWheelRouter()
        let decision = Self.verticalScrollEvent(deltaY: -3, window: timeline.window)
            .map { router.route(event: $0, from: codeView) }
        print("[wheel-e2e] forwardedToTimeline=\(forwarded) decision=\(String(describing: decision)) "
            + "origin \(before) -> \(after) docHeight=\(timeline.documentView?.frame.height ?? -1) "
            + "clipHeight=\(timeline.contentView.bounds.height)")

        XCTAssertNotEqual(
            after,
            before,
            accuracy: 0.5,
            "a vertical wheel over the code text did not move the timeline "
                + "(origin stayed at \(before)) — the page is frozen while hovering code"
        )
    }

    private func firstView<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstView(ofType: type, in: subview) { return match }
        }
        return nil
    }

    private static func verticalScrollEvent(deltaY: Int32, window: NSWindow?) -> NSEvent? {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        if let window {
            cgEvent.location = CGPoint(x: window.frame.midX, y: window.frame.midY)
        }
        return NSEvent(cgEvent: cgEvent)
    }

    /// SHORT code leaves most of a full-width card empty, and that empty area
    /// used to belong to the SwiftUI horizontal scroll view — which eats
    /// vertical wheels. Every point of the card must land on a view that
    /// forwards them (the code text view or the gutter), so the page keeps
    /// scrolling wherever the pointer sits.
    func testShortCodeFillsTheCardWithForwardingViews() {
        for gutter in [false, true] {
            let (timeline, host) = realize(source: Self.shortSource, showLineNumbers: gutter)
            var offenders: [String] = []
            let bounds = host.bounds
            for column in 0..<12 {
                for row in 0..<5 {
                    let point = NSPoint(
                        x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / 12,
                        y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / 5
                    )
                    let inWindow = host.convert(point, to: nil)
                    guard let hit = timeline.hitTest(inWindow) else { continue }
                    // Only points INSIDE the code body matter; the header and
                    // the card's padding are outside the scroll view.
                    var insideScrollView = false
                    var node: NSView? = hit
                    while let current = node, current !== timeline {
                        if current is NSScrollView, current !== timeline { insideScrollView = true }
                        node = current.superview
                    }
                    guard insideScrollView else { continue }
                    let forwards = routing(from: hit, timeline: timeline).hasPrefix("forwards")
                    if !forwards {
                        offenders.append("(\(Int(point.x)),\(Int(point.y))) -> \(type(of: hit))")
                    }
                }
            }
            XCTAssertTrue(
                offenders.isEmpty,
                "[gutter=\(gutter)] \(offenders.count) points inside the code body do not belong to a "
                    + "wheel-forwarding view: \(offenders.prefix(6).joined(separator: ", "))"
            )
        }
    }

    /// The decisive check: take the view AppKit would actually deliver the
    /// wheel to for a given point inside a code block, hand it a real scroll
    /// event, and see whether the timeline moves. Hit-testing to "some view
    /// inside the code block" says nothing on its own — what matters is
    /// whether the page still scrolls from there.
    func testEveryPointInACodeBlockScrollsTheTimeline() throws {
        for (label, source, gutter) in [
            ("overflow", Self.overflowingSource, false),
            ("overflow+gutter", Self.overflowingSource, true),
            ("short", Self.shortSource, false),
            ("short+gutter", Self.shortSource, true),
        ] as [(String, String, Bool)] {
            let (timeline, host) = realize(source: source, showLineNumbers: gutter)
            timeline.documentView?.setFrameSize(NSSize(width: blockWidth, height: 4_000))
            timeline.layoutSubtreeIfNeeded()

            var frozen: [String] = []
            let bounds = host.bounds
            for column in 0..<10 {
                for row in 0..<6 {
                    let point = NSPoint(
                        x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / 10,
                        y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / 6
                    )
                    let inWindow = host.convert(point, to: nil)
                    guard let hit = timeline.hitTest(inWindow) else { continue }

                    timeline.contentView.setBoundsOrigin(NSPoint(x: 0, y: 1_000))
                    timeline.reflectScrolledClipView(timeline.contentView)
                    let before = timeline.contentView.bounds.origin.y
                    for _ in 0..<2 {
                        guard let event = Self.verticalScrollEvent(deltaY: 3, window: timeline.window) else {
                            throw XCTSkip("cannot synthesize scroll events here")
                        }
                        hit.scrollWheel(with: event)
                        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    if abs(timeline.contentView.bounds.origin.y - before) < 0.5 {
                        frozen.append("(\(Int(point.x)),\(Int(point.y))) -> \(type(of: hit))")
                    }
                }
            }
            XCTAssertTrue(
                frozen.isEmpty,
                "[\(label)] the page does not scroll from \(frozen.count)/60 points inside the code "
                    + "block: \(frozen.prefix(8).joined(separator: ", "))"
            )
        }
    }

    /// Dispatch through `NSWindow.sendEvent` instead of calling
    /// `scrollWheel(with:)` on the hit view. Only this exercises AppKit's own
    /// routing, which is where a nested scroll view can CLAIM the gesture
    /// before our override ever runs — the mechanism this whole forwarding
    /// scheme exists to defeat.
    func testWindowDispatchedWheelOverCodeScrollsTheTimeline() throws {
        let (timeline, host) = realize(source: Self.overflowingSource, showLineNumbers: true)
        timeline.documentView?.setFrameSize(NSSize(width: blockWidth, height: 4_000))
        timeline.layoutSubtreeIfNeeded()
        guard let window = timeline.window else { return XCTFail("no window") }
        window.setFrameOrigin(NSPoint(x: 200, y: 200))
        guard let screenHeight = NSScreen.screens.first?.frame.height else {
            throw XCTSkip("no screen")
        }

        guard let codeView = firstView(ofType: JinMessageTextView.self, in: host) else {
            return XCTFail("no code text view")
        }
        let centre = codeView.convert(NSPoint(x: codeView.bounds.midX, y: codeView.bounds.midY), to: nil)
        let inScreen = window.convertPoint(toScreen: centre)
        let global = CGPoint(x: inScreen.x, y: screenHeight - inScreen.y)

        timeline.contentView.setBoundsOrigin(NSPoint(x: 0, y: 1_000))
        timeline.reflectScrolledClipView(timeline.contentView)
        let before = timeline.contentView.bounds.origin.y

        for _ in 0..<3 {
            guard let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: 3,
                wheel2: 0,
                wheel3: 0
            ) else { throw XCTSkip("cannot synthesize") }
            cgEvent.location = global
            guard let event = NSEvent(cgEvent: cgEvent) else { throw XCTSkip("cannot wrap") }
            guard event.window != nil else {
                throw XCTSkip("synthesized event has no window target in this environment")
            }
            window.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        XCTAssertNotEqual(
            timeline.contentView.bounds.origin.y,
            before,
            accuracy: 0.5,
            "window-dispatched wheel over the code text did not scroll the timeline"
        )
    }



}
