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

    /// `realize` drives the gutter through the real preference, which lives in
    /// the standard suite — i.e. the developer's own app defaults. Snapshot and
    /// restore it, or running the suite silently rewrites their setting and
    /// leaves every later test reading whatever the last case set.
    private var savedShowLineNumbers: Any?

    override func setUp() {
        super.setUp()
        savedShowLineNumbers = UserDefaults.standard.object(forKey: AppPreferenceKeys.codeBlockShowLineNumbers)
    }

    override func tearDown() {
        if let savedShowLineNumbers {
            UserDefaults.standard.set(savedShowLineNumbers, forKey: AppPreferenceKeys.codeBlockShowLineNumbers)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.codeBlockShowLineNumbers)
        }
        savedShowLineNumbers = nil
        super.tearDown()
    }

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

    /// Prints the live frames around column 0 so a CI failure names the
    /// actual hole (gutter width, code-view origin, inset, hit-test leaf)
    /// instead of only `(29,64) -> DocumentView`.
    private func describeHitLandscape(timeline: ChatTimelineScrollView, host: NSView) -> String {
        let gutter = firstView(ofType: CodeLineNumberTextView.self, in: host)
        let code = firstView(ofType: JinMessageTextView.self, in: host)
        var lines: [String] = []
        lines.append("host=\(host.bounds.size) fitting=\(host.fittingSize)")
        if let gutter {
            let inSuperview = NSPoint(x: gutter.frame.midX, y: gutter.frame.midY)
            lines.append(
                "gutter frame(in host)=\(gutter.convert(gutter.bounds, to: host)) "
                    + "bounds=\(gutter.bounds) inset=\(gutter.textContainerInset) "
                    + "intrinsic=\(gutter.intrinsicContentSize) "
                    + "hitInBounds=\(gutter.hitTest(inSuperview).map { String(describing: type(of: $0)) } ?? "nil")"
            )
        } else {
            lines.append("gutter=nil")
        }
        if let code {
            let frameInHost = code.convert(code.bounds, to: host)
            let sampleInHost = NSPoint(x: 29, y: 64)
            let sampleInSuperview = code.superview.map { host.convert(sampleInHost, to: $0) } ?? sampleInHost
            lines.append(
                "code frame(in host)=\(frameInHost) bounds=\(code.bounds) "
                    + "inset=\(code.textContainerInset) "
                    + "intrinsic=\(code.intrinsicContentSize) "
                    + "sampleInSuperview=\(sampleInSuperview) "
                    + "code.hitTest=\(code.hitTest(sampleInSuperview).map { String(describing: type(of: $0)) } ?? "nil")"
            )
        } else {
            lines.append("code=nil")
        }
        let sampleHit = timeline.hitTest(host.convert(NSPoint(x: 29, y: 64), to: nil))
        lines.append(
            "timeline.hitTest(29,64)=\(sampleHit.map { String(describing: type(of: $0)) } ?? "nil") "
                + "routing=\(sampleHit.map { routing(from: $0, timeline: timeline) } ?? "nil")"
        )
        return lines.joined(separator: "\n")
    }

    /// The CI failure was never a 1pt gutter/code seam: column 0 of the 12-wide
    /// grid (`x ≈ 29`) sits in the code view's 14pt leading `textContainerInset`.
    /// `NSTextView.hitTest` can return nil there, which the grid then reports
    /// as `DocumentView`. Pin the inset itself so a sizing-only "fix" cannot
    /// go green while the hole remains.
    func testCodeViewLeadingInsetHitTestsToForwarder() {
        let (timeline, host) = realize(source: Self.shortSource, showLineNumbers: true)
        guard let code = firstView(ofType: JinMessageTextView.self, in: host) else {
            return XCTFail("no code text view realized")
        }
        XCTAssertGreaterThan(code.textContainerInset.width, 2, "test assumes a leading inset")
        let local = NSPoint(x: 2, y: code.bounds.midY)
        let hit = timeline.hitTest(code.convert(local, to: nil))
        XCTAssertTrue(
            hit is JinMessageTextView,
            "2pt inside the code view's leading edge must stay on the code text "
                + "(hit \(hit.map { String(describing: type(of: $0)) } ?? "nil"))\n"
                + describeHitLandscape(timeline: timeline, host: host)
        )
    }

    func testGutterTrailingEdgeHitTestsToForwarder() {
        let (timeline, host) = realize(source: Self.shortSource, showLineNumbers: true)
        guard let gutter = firstView(ofType: CodeLineNumberTextView.self, in: host) else {
            return XCTFail("no gutter text view realized")
        }
        let local = NSPoint(x: max(gutter.bounds.maxX - 2, gutter.bounds.midX), y: gutter.bounds.midY)
        let hit = timeline.hitTest(gutter.convert(local, to: nil))
        XCTAssertTrue(
            hit is CodeLineNumberTextView,
            "2pt inside the gutter's trailing edge must stay on the gutter "
                + "(hit \(hit.map { String(describing: type(of: $0)) } ?? "nil"))\n"
                + describeHitLandscape(timeline: timeline, host: host)
        )
    }

    func testMessageTextViewClaimsHitsInTextContainerInset() {
        let view = JinMessageTextView()
        view.textContainerInset = NSSize(width: 14, height: 10)
        view.textStorage?.setAttributedString(
            NSAttributedString(
                string: "let x = 1",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
            )
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.frame = host.bounds
        host.addSubview(view)
        let hit = view.hitTest(NSPoint(x: 3, y: 20))
        XCTAssertTrue(
            hit === view,
            "left textContainerInset must hit-test to the text view, not nil "
                + "(hit \(hit.map { String(describing: type(of: $0)) } ?? "nil"))"
        )
    }

    func testHitTestingHelperClaimsInBoundsWhenSuperDeclines() {
        let view = NSView(frame: NSRect(x: 10, y: 20, width: 50, height: 30))
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        host.addSubview(view)
        let claimed = CodeBlockHitTesting.hitTest(
            view,
            pointInSuperview: NSPoint(x: 12, y: 25),
            superHit: nil
        )
        XCTAssertTrue(claimed === view)
        XCTAssertNil(
            CodeBlockHitTesting.hitTest(
                view,
                pointInSuperview: NSPoint(x: 0, y: 0),
                superHit: nil
            )
        )
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
                    + "wheel-forwarding view: \(offenders.prefix(6).joined(separator: ", "))\n"
                    + describeHitLandscape(timeline: timeline, host: host)
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
