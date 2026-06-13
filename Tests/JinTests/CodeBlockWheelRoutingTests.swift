import AppKit
import XCTest
@testable import Jin

/// Coverage for the load-bearing, testable half of the code-block scroll-trap
/// fix: resolving the enclosing `ChatTimelineScrollView` by a superview walk.
/// (The wheel-routing itself depends on AppKit hit-testing + real scroll
/// NSEvents, which have no public initializer, so the `route(...)` axis logic
/// is verified by reasoning/manual test, not here.)
@MainActor
final class CodeBlockWheelRoutingTests: XCTestCase {

    func testResolvesTimelineAcrossNestedHierarchy() {
        // Mirror the real shape: timeline scroll view -> clip -> document ->
        // hosting layers -> the code text view, several levels deep.
        let timeline = ChatTimelineScrollView()
        let clip = NSView()
        let document = NSView()
        let hostingLike = NSView()
        let leaf = NSView()

        timeline.addSubview(clip)
        clip.addSubview(document)
        document.addSubview(hostingLike)
        hostingLike.addSubview(leaf)

        XCTAssertTrue(
            CodeBlockWheelRouter.enclosingTimelineScrollView(from: leaf) === timeline
        )
        // From an intermediate node too.
        XCTAssertTrue(
            CodeBlockWheelRouter.enclosingTimelineScrollView(from: hostingLike) === timeline
        )
    }

    func testReturnsNilWhenNoTimelineAncestor() {
        // A JinMessageTextView used outside the timeline (e.g. a preview) must
        // fall back to nil so the override degenerates to default behavior.
        let root = NSView()
        let mid = NSView()
        let leaf = NSView()
        root.addSubview(mid)
        mid.addSubview(leaf)

        XCTAssertNil(CodeBlockWheelRouter.enclosingTimelineScrollView(from: leaf))
    }

    func testReturnsNilForDetachedView() {
        // No superview at all.
        XCTAssertNil(CodeBlockWheelRouter.enclosingTimelineScrollView(from: NSView()))
    }

    func testPlainNSScrollViewAncestorIsNotMistakenForTimeline() {
        // The resolver matches the CONCRETE timeline type, never a generic
        // NSScrollView (e.g. the trapping SwiftUI horizontal scroll host),
        // which is exactly why forwarding escapes the trap instead of
        // re-entering it.
        let plainScrollView = NSScrollView()
        let leaf = NSView()
        plainScrollView.addSubview(leaf)

        XCTAssertNil(CodeBlockWheelRouter.enclosingTimelineScrollView(from: leaf))
    }
}
