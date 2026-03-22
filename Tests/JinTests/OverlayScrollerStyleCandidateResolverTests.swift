import XCTest
import AppKit
@testable import Jin

@MainActor
final class OverlayScrollerStyleCandidateResolverTests: XCTestCase {
    private var rootView: NSView!

    override func setUp() {
        super.setUp()
        rootView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    }

    override func tearDown() {
        rootView = nil
        super.tearDown()
    }

    func testResolverReturnsEnclosingScrollViewWhenProbeIsInsideDocumentView() {
        let scrollView = makeScrollView(frame: NSRect(x: 20, y: 20, width: 240, height: 320))
        rootView.addSubview(scrollView)

        let probe = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 320))
        scrollView.documentView?.addSubview(probe)

        let resolved = OverlayScrollViewCandidateResolver().resolveBestCandidate(for: probe)

        XCTAssertTrue(resolved === scrollView)
    }

    func testResolverPrefersIntersectingSiblingScrollViewOverUnrelatedPane() {
        let sidebarBackgroundHost = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 700))
        let detailBackgroundHost = NSView(frame: NSRect(x: 280, y: 0, width: 620, height: 700))
        let sidebarScrollView = makeScrollView(frame: sidebarBackgroundHost.frame)
        let detailScrollView = makeScrollView(frame: detailBackgroundHost.frame)

        rootView.addSubview(sidebarBackgroundHost)
        rootView.addSubview(sidebarScrollView)
        rootView.addSubview(detailBackgroundHost)
        rootView.addSubview(detailScrollView)

        let probe = NSView(frame: sidebarBackgroundHost.bounds)
        sidebarBackgroundHost.addSubview(probe)

        let resolved = OverlayScrollViewCandidateResolver().resolveBestCandidate(for: probe)

        XCTAssertTrue(resolved === sidebarScrollView)
    }

    func testResolverFindsNestedSiblingScrollViewInsideWrapper() {
        let hostContainer = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))
        let backgroundHost = NSView(frame: hostContainer.bounds)
        let scrollWrapper = NSView(frame: hostContainer.bounds)
        let scrollView = makeScrollView(frame: scrollWrapper.bounds)

        rootView.addSubview(hostContainer)
        hostContainer.addSubview(backgroundHost)
        hostContainer.addSubview(scrollWrapper)
        scrollWrapper.addSubview(scrollView)

        let probe = NSView(frame: backgroundHost.bounds)
        backgroundHost.addSubview(probe)

        let resolved = OverlayScrollViewCandidateResolver().resolveBestCandidate(for: probe)

        XCTAssertTrue(resolved === scrollView)
    }

    private func makeScrollView(frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        let documentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        return scrollView
    }
}
