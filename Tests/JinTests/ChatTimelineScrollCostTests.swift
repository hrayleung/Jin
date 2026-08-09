import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// Measures what a scroll actually costs, because "scrolling got laggy" has to
/// be diagnosed with numbers, not by reading diffs.
///
/// The app's proven cost model: scroll-frame time is linear in the number of
/// resident `JinMessageTextView` bridges, and TextKit layout over a long
/// message is the dominant per-block cost. So the two things to count while
/// dragging through a conversation are (a) how many full text copies +
/// `ensureLayout` passes the shared measuring stack performs, and (b) wall
/// time per scroll step.
@MainActor
final class ChatTimelineScrollCostTests: XCTestCase {

    private let windowWidth: CGFloat = 1_800
    private let windowHeight: CGFloat = 1_300

    private var columnWidth: CGFloat {
        ChatConversationLayoutMetrics.messageColumnWidth(for: windowWidth)
    }

    /// A conversation big enough that recycling is doing real work.
    private func makeItems() -> [MessageRenderItem] {
        var items: [MessageRenderItem] = []
        for _ in 0..<4 {
            items.append(contentsOf: TimelineRowFixtures.reportedConversation())
        }
        return items
    }

    func testScrollingThroughHistoryStaysCheap() throws {
        let harness = ChatTimelineControllerRowGeometryTests.Harness(
            items: makeItems(),
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight)
        )
        harness.settle(seconds: 1.5)

        // Baseline the counters AFTER the initial open, so we measure scrolling.
        JinTextMeasurementStack.copyCount = 0
        JinTextMeasurementStack.layoutCount = 0
        JinTextMeasurementStack.copiesByKind = [:]
        JinLayoutCostCounters.reset()

        let documentHeight = harness.tableView.frame.height
        var offsets: [CGFloat] = []
        var y = documentHeight
        // ~40 steps of a quarter viewport: a realistic drag through history.
        while y > 0, offsets.count < 40 {
            offsets.append(y)
            y -= windowHeight * 0.25
        }

        let started = ProcessInfo.processInfo.systemUptime
        for offset in offsets {
            harness.scroll(to: offset)
            harness.settle(seconds: 0.02)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        let copies = JinTextMeasurementStack.copyCount
        let layouts = JinTextMeasurementStack.layoutCount
        let perStep = elapsed / Double(offsets.count)

        print("""
        [scroll-cost] steps=\(offsets.count) rows=\(harness.tableView.numberOfRows)
          measuring-stack copies  = \(copies)   (\(String(format: "%.1f", Double(copies) / Double(offsets.count)))/step)
          measuring-stack layouts = \(layouts)  (\(String(format: "%.1f", Double(layouts) / Double(offsets.count)))/step)
          wall time               = \(String(format: "%.0f", elapsed * 1000))ms total, \
        \(String(format: "%.1f", perStep * 1000))ms/step
          copies by call site     = \(JinTextMeasurementStack.copiesByKind)
          shadow layouts          = \(JinLayoutCostCounters.shadowLayouts)
          live measure layouts    = \(JinLayoutCostCounters.liveMeasureLayouts)
          mid-edit fallbacks      = \(JinLayoutCostCounters.midEditMeasurements)
          cell frame syncs        = \(JinLayoutCostCounters.cellFrameSyncs)
          cell configures         = \(JinLayoutCostCounters.cellConfigures)
          height audits           = \(JinLayoutCostCounters.heightAudits)         (rows sampled \(JinLayoutCostCounters.auditRowsSampled))
        """)

        // The regression this pins: a scroll step must not re-copy and
        // re-lay-out the visible text on a second TextKit stack. When the
        // shared measuring stack was on the width-probe path this measured
        // 809 copies / 936 layouts across these same 40 steps; per-view shadow
        // layout managers (which share the storage) make it zero.
        XCTAssertLessThan(
            Double(copies) / Double(offsets.count),
            1,
            "the shared measuring stack re-copies the full text \(copies) times over \(offsets.count) "
                + "scroll steps — every copy discards its glyphs and re-runs ensureLayout, which is "
                + "exactly the per-frame cost the recycling rewrite exists to avoid"
        )
        // The per-view shadow layout managers share the live storage, so each
        // off-width probe is an `ensureLayout` on a second manager. Cheap
        // individually, but they must stay proportional to the rows the scroll
        // realizes rather than growing per frame. Measured on this fixture:
        // 635 across the 40 steps (15.9/step) against 187 cell configures.
        let shadowPerStep = Double(JinLayoutCostCounters.shadowLayouts) / Double(offsets.count)
        XCTAssertLessThan(
            shadowPerStep,
            40,
            "\(String(format: "%.1f", shadowPerStep)) shadow layouts per scroll step — the off-width "
                + "probe path is re-laying-out far more than the rows a step realizes"
        )
        // The mid-edit safety valve (a probe that arrived while a storage edit
        // was still fanning out, answered on the isolated stack for a full
        // string copy) must never be on the scroll path. Anything above zero
        // here means measurement and mutation have started interleaving again.
        XCTAssertEqual(
            JinLayoutCostCounters.midEditMeasurements,
            0,
            "\(JinLayoutCostCounters.midEditMeasurements) sizing probes were answered from inside a "
                + "storage edit — each one is a full-text copy, and each one would have been the "
                + "build-658 crash before the guard existed"
        )
        // Wall time here is dominated by cell realization plus this harness's
        // own 20ms-per-step run-loop settle, and it is noisy run to run —
        // especially on a loaded or slower machine — so this is a catastrophe
        // detector, deliberately several multiples above the measurements, not
        // a target. The deterministic guard is the copy count above. Reference
        // points on this fixture: 88.3ms/step on b3d048d (before the timeline
        // fixes), ~70-78ms/step now.
        XCTAssertLessThan(
            perStep * 1000,
            400,
            "a scroll step costs \(String(format: "%.1f", perStep * 1000))ms (pre-fix baseline was 88ms)"
        )
    }

    /// Streaming is the other hot path: every delta re-runs `sizeThatFits` for
    /// the tail block while an apply is pending.
    func testStreamingDeltasStayCheap() throws {
        let harness = ChatTimelineControllerRowGeometryTests.Harness(
            items: TimelineRowFixtures.reportedConversation(),
            shared: TimelineRowFixtures.shared(columnWidth: columnWidth),
            size: NSSize(width: windowWidth, height: windowHeight)
        )
        harness.settle(seconds: 1.2)

        let state = StreamingMessageState()
        harness.startStreaming(state)
        harness.settle(seconds: 0.3)

        JinTextMeasurementStack.copyCount = 0
        JinTextMeasurementStack.layoutCount = 0
        JinLayoutCostCounters.reset()

        let started = ProcessInfo.processInfo.systemUptime
        var deltas = 0
        for chunk in TimelineRowFixtures.assistantReply.split(separator: " ") {
            state.appendTextDelta(String(chunk) + " ")
            harness.apply()
            harness.settle(seconds: 0.01)
            deltas += 1
            if deltas >= 40 { break }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        print("""
        [stream-cost] deltas=\(deltas)
          measuring-stack copies  = \(JinTextMeasurementStack.copyCount)
          measuring-stack layouts = \(JinTextMeasurementStack.layoutCount)
          shadow layouts          = \(JinLayoutCostCounters.shadowLayouts)
          live measure layouts    = \(JinLayoutCostCounters.liveMeasureLayouts)
          mid-edit fallbacks      = \(JinLayoutCostCounters.midEditMeasurements)
          wall time               = \(String(format: "%.0f", elapsed * 1000))ms total, \
        \(String(format: "%.1f", elapsed / Double(deltas) * 1000))ms/delta
        """)

        // Streaming is where the shadow stack could quietly become expensive:
        // it shares the live `NSTextStorage`, so every delta invalidates it,
        // and the tail block is re-sized on every one of them. Measured: 2
        // shadow layouts across these 40 deltas (0.05/delta) against 41 live
        // ones — the edit stream drives the LIVE path, not this one. The bound
        // is what "one shadow layout per delta" would break.
        let shadowPerDelta = Double(JinLayoutCostCounters.shadowLayouts) / Double(deltas)
        XCTAssertLessThan(
            shadowPerDelta,
            1,
            "\(String(format: "%.1f", shadowPerDelta)) shadow layouts per streaming delta — the "
                + "off-width probe path is being driven by the edit stream"
        )
        // Streaming is where the crash reproduced. Zero here says the applies
        // and the sizing probes are not interleaving: no probe landed inside
        // an edit, so none had to be answered off the isolated stack.
        XCTAssertEqual(
            JinLayoutCostCounters.midEditMeasurements,
            0,
            "\(JinLayoutCostCounters.midEditMeasurements) sizing probes arrived from inside a "
                + "storage edit while streaming"
        )
        XCTAssertLessThan(
            elapsed / Double(deltas) * 1000,
            120,
            "a streaming delta costs \(String(format: "%.1f", elapsed / Double(deltas) * 1000))ms"
        )
    }
}
