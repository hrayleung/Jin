import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// End-to-end geometry probe for the recycling timeline: drives the REAL
/// `ChatTimelineTableController` through the real apply/reconcile/measure/audit
/// paths with a conversation shaped like the one that reproduced the
/// "clipped bubble + one-viewport gap" report, then reads back, per row:
///
///   * the height AppKit applied (row view frame),
///   * the height of the cell that clips the content (`clipsToBounds`),
///   * the height of the SwiftUI hosting view (the paint slot),
///   * the height the cell reports as needed,
///   * and the bottom of the actually-painted pixels.
///
/// Static per-row measurement (`ChatTimelineRowPaintGeometryTests`) already
/// passes; every remaining defect in this family lives in the dynamic paths —
/// estimate→measure corrections, recycling, and the post-settle audit — which
/// is exactly what this exercises.
@MainActor
final class ChatTimelineControllerRowGeometryTests: XCTestCase {

    private let windowWidth: CGFloat = 1_800
    private let windowHeight: CGFloat = 1_300
    private var columnWidth: CGFloat {
        ChatConversationLayoutMetrics.messageColumnWidth(for: windowWidth)
    }

    // MARK: - Cases

    func testConversationOpenLeavesNoClippedOrGappedRow() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.4) // past the 700ms conversation-open audit
        try assertAllResidentRowsAreClean(harness, phase: "conversation-open")
    }

    func testScrollingThroughHistoryLeavesNoClippedOrGappedRow() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.4)

        // Walk up through the whole document a viewport at a time, then back
        // down: this recycles every cell at least twice.
        var offsets: [CGFloat] = []
        let documentHeight = harness.tableView.frame.height
        var y = documentHeight
        while y > 0 {
            offsets.append(y)
            y -= windowHeight * 0.75
        }
        offsets.append(0)
        offsets.append(contentsOf: offsets.reversed())

        for offset in offsets {
            harness.scroll(to: offset)
            harness.settle(seconds: 0.15)
        }
        harness.settle(seconds: 1.0)
        try assertAllResidentRowsAreClean(harness, phase: "after-scroll")
    }

    func testAppendingAMessageLeavesNoClippedOrGappedRow() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.4)

        harness.appendMessage(
            TimelineRowFixtures.item(role: "assistant", text: TimelineRowFixtures.assistantReply)
        )
        harness.settle(seconds: 1.4)
        try assertAllResidentRowsAreClean(harness, phase: "after-append")
    }

    /// The send path: a streaming row grows a chunk at a time, re-noting its
    /// own height on every flush. It is the row most exposed to a clip box
    /// that doesn't track the row height, because it re-sizes dozens of times.
    func testStreamingRowGrowsWithoutClippingOrGapping() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.0)

        let state = StreamingMessageState()
        harness.startStreaming(state)
        harness.settle(seconds: 0.3)

        for paragraph in TimelineRowFixtures.assistantReply.split(separator: "\n\n") {
            state.appendTextDelta(String(paragraph) + "\n\n")
            harness.apply()
            harness.settle(seconds: 0.12)
        }
        harness.settle(seconds: 1.0)
        try assertAllResidentRowsAreClean(harness, phase: "while-streaming")
    }

    /// Rows that SHRINK after the table has already laid them out — the
    /// "open a conversation and the top of a reply is missing until you
    /// scroll" case. `NSTableCellView` is NOT a flipped view, so a subview
    /// pinned to its top is bottom-anchored in raw coordinates: shrink the
    /// cell without re-running its constraints and the hosted content keeps
    /// its old position, riding up past the cell's top edge where the mask
    /// cuts it off.
    ///
    /// Driven through the real warm-start path: a too-tall stored height is
    /// seeded on open (exactly what a stale measurement does in production),
    /// so every row opens oversized and then corrects downward.
    func testRowsThatOpenTooTallAndShrinkStayTopAligned() throws {
        let conversationID = UUID()
        let items = TimelineRowFixtures.reportedConversation()
        let widthBucket = Int(ceil(max(1, columnWidth)))
        let environmentToken = ChatTimelineRowHeightStore.environmentToken()
        for item in items {
            ChatTimelineRowHeightStore.shared.store(
                2_400,
                for: ChatTimelineRowHeightStore.Key(
                    conversationID: conversationID,
                    rowIdentity: "msg-\(item.id.uuidString)",
                    widthBucket: widthBucket,
                    contentSignature: ChatTimelineRowHeightStore.contentSignature(for: item.copyText),
                    environmentToken: environmentToken
                )
            )
        }

        let harness = Harness(
            items: items,
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight),
            conversationID: conversationID
        )
        harness.settle(seconds: 1.6)
        try assertAllResidentRowsAreClean(harness, phase: "after-shrink-from-seed")
    }

    func testResizingTheWindowLeavesNoClippedOrGappedRow() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.4)

        // Narrow, then widen: both re-wrap every row and wipe the height
        // caches, so every row goes through estimate→measure a second time.
        for width in [1_240.0, 1_640.0, 900.0] as [CGFloat] {
            harness.resize(width: width)
            harness.settle(seconds: 0.9)
        }
        harness.settle(seconds: 1.0)
        try assertAllResidentRowsAreClean(harness, phase: "after-resize")
    }

    /// Pins the AppKit geometry contract every scroll-compensation delta in
    /// the controller depends on: `heightOfRow` returns the CONTENT height,
    /// while both `rect(ofRow:)` and the row view's frame are that height
    /// PLUS the intercell spacing. Comparing a measured content height against
    /// either of the latter reads as a permanent 16pt error — which showed up
    /// in production as an audit "correction" on every settled row
    /// (`applied == measured + 16` in every logged sample) and a 16pt-per-row
    /// scroll lurch to go with it.
    func testRowRectIncludesIntercellSpacingButHeightOfRowDoesNot() throws {
        let harness = try makeHarness()
        harness.settle(seconds: 1.4)

        let spacing = harness.tableView.intercellSpacing.height
        XCTAssertGreaterThan(spacing, 0, "fixture must exercise a spaced table")

        var checked = 0
        harness.tableView.enumerateAvailableRowViews { rowView, row in
            let declared = harness.controller.tableView(harness.tableView, heightOfRow: row)
            XCTAssertEqual(harness.tableView.rect(ofRow: row).height, declared + spacing, accuracy: 0.5)
            XCTAssertEqual(rowView.frame.height, declared + spacing, accuracy: 0.5)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - The invariant

    private func assertAllResidentRowsAreClean(
        _ harness: Harness,
        phase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let samples = harness.sampleResidentRows()
        XCTAssertFalse(samples.isEmpty, "\(phase): no resident rows to inspect", file: file, line: line)

        for sample in samples {
            print("""
            [controller-geometry:\(phase)] row \(sample.row) \(sample.identity)
              rowView.frame.height = \(sample.rowViewHeight)
              cell.frame.height    = \(sample.cellHeight)   <- clip boundary
              host.frame.height    = \(sample.hostHeight)   <- paint slot
              host top inside cell = \(sample.hostTopInsideCell)
              measuredContent      = \(sample.measuredHeight)
              painted              = \(sample.paintedTop)...\(sample.paintedBottom)
            """)
        }

        for sample in samples where sample.cellHeight > 2 {
            XCTAssertLessThanOrEqual(
                sample.measuredHeight,
                sample.cellHeight + 1,
                "\(phase) row \(sample.row): content needs \(sample.measuredHeight)pt but the cell clips at "
                    + "\(sample.cellHeight)pt — bottom of the message is cut off",
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(
                sample.hostHeight,
                sample.cellHeight - 1,
                "\(phase) row \(sample.row): SwiftUI paint slot is \(sample.hostHeight)pt inside a "
                    + "\(sample.cellHeight)pt cell — nothing paints below the slot",
                file: file,
                line: line
            )
            XCTAssertEqual(
                sample.hostTopInsideCell,
                0,
                accuracy: 1,
                "\(phase) row \(sample.row): content starts \(sample.hostTopInsideCell)pt from the cell's top "
                    + "— anything above that is masked away (header/first lines cut off)",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                sample.paintedTop,
                24,
                "\(phase) row \(sample.row): first painted pixel is \(sample.paintedTop)pt down — "
                    + "the top of the message is cut off",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                sample.cellHeight - sample.paintedBottom,
                14,
                "\(phase) row \(sample.row): cell reserves \(sample.cellHeight)pt but paint stops at "
                    + "\(sample.paintedBottom)pt — \(sample.cellHeight - sample.paintedBottom)pt blank gap",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Harness

    struct RowSample {
        let row: Int
        let identity: String
        let rowViewHeight: CGFloat
        let cellHeight: CGFloat
        let hostHeight: CGFloat
        let hostTopInsideCell: CGFloat
        let measuredHeight: CGFloat
        let paintedTop: CGFloat
        let paintedBottom: CGFloat
    }

    @MainActor
    final class Harness {
        let controller: ChatTimelineTableController
        let window: NSWindow
        let scrollView: NSScrollView
        let tableView: NSTableView
        private let conversationID: UUID
        private var items: [MessageRenderItem]
        private var shared: ChatTimelineSharedInputs
        private var epochSeed = 0

        init(
            items: [MessageRenderItem],
            shared: ChatTimelineSharedInputs,
            size: NSSize,
            conversationID: UUID = UUID()
        ) {
            self.items = items
            self.shared = shared
            self.conversationID = conversationID
            controller = ChatTimelineTableController()
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            controller.view.frame = NSRect(origin: .zero, size: size)
            window.contentView = controller.view
            scrollView = controller.view as! NSScrollView
            tableView = scrollView.documentView as! NSTableView
            apply()
        }

        private var streaming: StreamingMessageState?

        /// Re-pushes content with a fresh epoch (what a preference change
        /// does): forces every resident cell to rebuild and re-measure.
        func bumpEpochAndApply() {
            epochSeed += 1
            apply()
        }

        func startStreaming(_ state: StreamingMessageState) {
            streaming = state
            apply()
        }

        func appendMessage(_ item: MessageRenderItem) {
            items.append(item)
            epochSeed += 1
            apply()
        }

        func apply() {
            var rows = items.enumerated().map { ChatTimelineRow.message($1, index: $0) }
            if let streaming {
                rows.append(.streaming(streaming))
            }
            controller.apply(
                ChatTimelineTableController.Model(
                    conversationID: conversationID,
                    rows: rows,
                    shared: shared,
                    contentEpoch: TimelineRowFixtures.epoch(entityCount: items.count + epochSeed),
                    streamingMessage: streaming,
                    topInset: 12,
                    bottomInset: 120,
                    bottomTolerance: 24,
                    nextRenderLimit: 200,
                    canLoadEarlier: false,
                    setPinned: { _ in },
                    setRenderLimit: { _ in },
                    onLoadEarlier: {}
                )
            )
        }

        /// Mirrors a window resize: the view gets the new width and the next
        /// apply carries the re-derived column width (what ChatView does).
        func resize(width: CGFloat) {
            let size = NSSize(width: width, height: window.frame.height)
            window.setContentSize(size)
            controller.view.frame = NSRect(origin: .zero, size: size)
            controller.view.layoutSubtreeIfNeeded()
            shared = TimelineRowFixtures.shared(
                columnWidth: ChatConversationLayoutMetrics.messageColumnWidth(for: width)
            )
            apply()
        }

        func scrollToBottomOfDocument() {
            scroll(to: max(0, tableView.frame.height - scrollView.contentView.bounds.height))
        }

        /// The code text view inside a horizontally-scrollable code block —
        /// i.e. one with a non-timeline `NSScrollView` between it and the
        /// timeline. Plain prose text views don't sit in one.
        func firstCodeBlockTextView() -> JinMessageTextView? {
            var found: JinMessageTextView?
            func walk(_ view: NSView) {
                if found != nil { return }
                if let candidate = view as? JinMessageTextView {
                    var node: NSView? = candidate.superview
                    while let current = node, current !== scrollView {
                        if let inner = current as? NSScrollView, inner !== scrollView,
                           (inner.documentView?.frame.width ?? 0) > inner.contentView.bounds.width + 1 {
                            found = candidate
                            return
                        }
                        node = current.superview
                    }
                }
                for sub in view.subviews { walk(sub) }
            }
            walk(tableView)
            if found == nil {
                var report: [String] = []
                func survey(_ view: NSView) {
                    if let candidate = view as? JinMessageTextView {
                        var chain: [String] = []
                        var node: NSView? = candidate.superview
                        while let current = node, current !== scrollView {
                            if let inner = current as? NSScrollView {
                                chain.append("\(type(of: inner)) doc=\(inner.documentView?.frame.width ?? -1) vis=\(inner.contentView.bounds.width)")
                            }
                            node = current.superview
                        }
                        report.append("textView w=\(candidate.frame.width) scrollAncestors=\(chain)")
                    }
                    for sub in view.subviews { survey(sub) }
                }
                survey(tableView)
                print("[wheel-probe] no overflowing code block; candidates:\n  " + report.joined(separator: "\n  "))
            }
            return found
        }

        func scroll(to y: CGFloat) {
            let clip = scrollView.contentView
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clip)
        }

        func settle(seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                window.contentView?.layoutSubtreeIfNeeded()
            }
            window.contentView?.displayIfNeeded()
        }

        func sampleResidentRows() -> [RowSample] {
            var samples: [RowSample] = []
            tableView.enumerateAvailableRowViews { rowView, row in
                guard let cell = rowView.view(atColumn: 0) as? ChatTimelineHostingCell,
                      let identity = cell.currentIdentity else { return }
                // Diagnostic: does forcing the ROW VIEW to lay out re-frame
                // the cell? (Answers "is the stale cell frame just a missing
                // layout pass?")
                cell.layoutSubtreeIfNeeded()
                let painted = Self.paintedRange(of: cell)
                // `NSTableCellView` is NOT flipped, so a top-pinned subview's
                // raw origin is bottom-anchored: convert to a distance from
                // the cell's visual top, which is what the mask cuts against.
                let hostTop = cell.isFlipped
                    ? cell.host.frame.minY
                    : cell.frame.height - cell.host.frame.maxY
                samples.append(
                    RowSample(
                        row: row,
                        identity: identity,
                        rowViewHeight: rowView.frame.height,
                        cellHeight: cell.frame.height,
                        hostHeight: cell.host.frame.height,
                        hostTopInsideCell: hostTop,
                        measuredHeight: cell.measuredContentHeight(),
                        paintedTop: painted.top,
                        paintedBottom: painted.bottom
                    )
                )
            }
            return samples.sorted { $0.row < $1.row }
        }

        /// Bottom edge of the painted (non-transparent) pixels, in the view's
        /// own coordinates. Honours `clipsToBounds` / layer masks, so it is
        /// literally what the user sees inside this row.
        @MainActor
        static func paintedRange(of view: NSView) -> (top: CGFloat, bottom: CGFloat) {
            guard view.bounds.height >= 1, view.bounds.width >= 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return (0, 0) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.bitmapData else { return (0, 0) }
            let bytesPerRow = rep.bytesPerRow
            let samples = rep.samplesPerPixel
            let scaleY = view.bounds.height / CGFloat(max(1, rep.pixelsHigh))
            var top = -1
            var bottom = -1
            for y in 0..<rep.pixelsHigh {
                let rowStart = data + y * bytesPerRow
                for x in 0..<rep.pixelsWide {
                    let pixel = rowStart + x * samples
                    let alpha = samples >= 4 ? pixel[3] : 255
                    if alpha > 8, samples >= 3, pixel[0] | pixel[1] | pixel[2] != 0 {
                        if top < 0 { top = y }
                        bottom = y
                        break
                    }
                }
            }
            guard bottom >= 0 else { return (0, 0) }
            return (CGFloat(top) * scaleY, CGFloat(bottom + 1) * scaleY)
        }
    }

    func makeHarness() throws -> Harness {
        Harness(
            items: TimelineRowFixtures.reportedConversation(),
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight)
        )
    }
}

// MARK: - Wheel routing through the real cell hierarchy

@MainActor
extension ChatTimelineControllerRowGeometryTests {

    /// The chat must keep scrolling while the pointer is over a code block.
    /// The block's horizontal scroll view eats vertical wheels, so the code
    /// text view forwards them to the timeline — through the recycling cell,
    /// the row view and the table, which is the hierarchy the isolated code
    /// block test does not exercise.
    func testWheelOverACodeBlockScrollsTheTimeline() throws {
        // A single wide-code turn plus filler, so the code block is certain to
        // be realized and the document is certain to be scrollable.
        var items = [TimelineRowFixtures.item(role: "assistant", text: TimelineRowFixtures.wideCodeReply)]
        items.append(contentsOf: TimelineRowFixtures.reportedConversation())
        let harness = Harness(
            items: items,
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight)
        )
        harness.settle(seconds: 1.4)
        harness.scroll(to: 0)
        harness.settle(seconds: 0.6)

        guard let codeView = harness.firstCodeBlockTextView() else {
            throw XCTSkip("no code block realized in the viewport")
        }

        let before = harness.scrollView.contentView.bounds.origin.y
        for _ in 0..<3 {
            guard let event = Self.lineScrollEvent(deltaY: 3, window: harness.window) else {
                throw XCTSkip("cannot synthesize scroll events here")
            }
            codeView.scrollWheel(with: event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let after = harness.scrollView.contentView.bounds.origin.y

        XCTAssertNotEqual(
            after,
            before,
            accuracy: 0.5,
            "wheeling over a code block left the timeline at \(before) — the page is frozen "
                + "while the pointer sits on code"
        )
    }

    /// A trackpad-style gesture: continuous (precise) deltas carrying a scroll
    /// phase. AppKit decides which scroll view OWNS a gesture at `.began` and
    /// routes the rest of it there, so a forwarded `.changed` can be ignored by
    /// a scroll view that never saw the start — which is exactly the difference
    /// between "works with a mouse wheel" and "frozen on a trackpad".
    func testTrackpadGestureOverACodeBlockScrollsTheTimeline() throws {
        var items = [TimelineRowFixtures.item(role: "assistant", text: TimelineRowFixtures.wideCodeReply)]
        items.append(contentsOf: TimelineRowFixtures.reportedConversation())
        let harness = Harness(
            items: items,
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight)
        )
        harness.settle(seconds: 1.4)
        harness.scroll(to: 0)
        harness.settle(seconds: 0.6)

        guard let codeView = harness.firstCodeBlockTextView() else {
            throw XCTSkip("no code block realized in the viewport")
        }

        let before = harness.scrollView.contentView.bounds.origin.y
        let phases: [(Int64, Double)] = [(1, 8), (2, 24), (2, 24), (2, 24), (4, 0)]
        for (phase, delta) in phases {
            guard let event = Self.trackpadScrollEvent(
                deltaY: delta,
                phase: phase,
                window: harness.window
            ) else {
                throw XCTSkip("cannot synthesize trackpad scroll events here")
            }
            codeView.scrollWheel(with: event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let after = harness.scrollView.contentView.bounds.origin.y

        XCTAssertNotEqual(
            after,
            before,
            accuracy: 0.5,
            "a trackpad gesture over a code block left the timeline at \(before) — the page is "
                + "frozen while the pointer sits on code"
        )
    }

    static func trackpadScrollEvent(deltaY: Double, phase: Int64, window: NSWindow?) -> NSEvent? {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        if let window {
            cgEvent.location = CGPoint(x: window.frame.midX, y: window.frame.midY)
        }
        return NSEvent(cgEvent: cgEvent)
    }

    static func lineScrollEvent(deltaY: Int32, window: NSWindow?) -> NSEvent? {
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
}
