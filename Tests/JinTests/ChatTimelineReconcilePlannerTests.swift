import XCTest
@testable import Jin

/// The planner decides which NSTableView mutation the timeline applies for an
/// old→new row-identity change. The batch cases must respect the
/// CollectionDifference/NSTableView coordinate contract (removals in OLD
/// coordinates, insertions in NEW), which `applyPlan` replays to prove.
final class ChatTimelineReconcilePlannerTests: XCTestCase {

    private let LE = "loadEarlier"
    private let ST = "streaming"

    private func msgs(_ range: ClosedRange<Int>) -> [String] {
        range.map { "msg-\($0)" }
    }

    // MARK: - Existing shapes (parity with the historical branches)

    func testIdenticalRowsPlanIdentical() {
        let ids = [LE] + msgs(1...5)
        XCTAssertEqual(ChatTimelineReconcilePlanner.plan(oldIDs: ids, newIDs: ids), .identical)
        XCTAssertEqual(ChatTimelineReconcilePlanner.plan(oldIDs: [], newIDs: []), .identical)
    }

    func testStreamingSwapPlansReloadInPlace() {
        let old = [LE] + msgs(1...4) + [ST]
        let new = [LE] + msgs(1...4) + ["msg-5"]
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new),
            .reloadInPlace(changed: IndexSet(integer: 5))
        )
    }

    func testAppendPlansAppendTail() {
        let old = msgs(1...4)
        let new = msgs(1...4) + ["msg-5", ST]
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new),
            .appendTail(inserted: 4..<6)
        )
    }

    func testAppendIntoEmptyPlansAppendTail() {
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: [], newIDs: msgs(1...3)),
            .appendTail(inserted: 0..<3)
        )
    }

    func testPurePrependPlansPrependHead() {
        let old = msgs(10...20)
        let new = msgs(5...20)
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new),
            .prependHead(inserted: 0..<5)
        )
    }

    // MARK: - Slide shapes (previously fullReload — the send white-beat)

    func testSteadyWindowSlidePlansBatchDiff() {
        // Send in a capped window: head message drops, user message + streaming
        // row append under a constant loadEarlier identity.
        let old = [LE] + msgs(1...24)
        let new = [LE] + msgs(2...24) + ["msg-25", ST]
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new),
            .batchDiff(removals: IndexSet(integer: 1), insertions: IndexSet([24, 25]))
        )
        assertReplay(old: old, new: new)
    }

    func testSlideWithLoadEarlierAppearingPlansBatchDiff() {
        // The conversation crosses the render cap: LE appears at the head while
        // the tail appends.
        let old = msgs(1...24)
        let new = [LE] + msgs(2...24) + ["msg-25"]
        assertReplay(old: old, new: new)
    }

    func testSlideCombinedWithStreamingSwapPlansBatchDiff() {
        // Stream finishes AND the window slides in the same apply.
        let old = [LE] + msgs(2...24) + [ST]
        let new = [LE] + msgs(3...25)
        assertReplay(old: old, new: new)
    }

    func testFinalLoadEarlierPagePlansBatchDiff() {
        // LE disappears while the remaining head prepends.
        let old = [LE] + msgs(10...30)
        let new = msgs(0...30)
        assertReplay(old: old, new: new)
    }

    func testLoadEarlierPageWithSurvivingHeaderPlansBatchDiff() {
        // Mid-history page: LE survives at the head, a page lands below it.
        let old = [LE] + msgs(10...30)
        let new = [LE] + msgs(5...30)
        assertReplay(old: old, new: new)
    }

    func testClearedConversationPlansBatchDiffWhenSmall() {
        let old = msgs(1...5)
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: []),
            .batchDiff(removals: IndexSet(0..<5), insertions: IndexSet())
        )
    }

    // MARK: - Fallback

    func testOversizedDiffPlansFullReload() {
        let old = msgs(1...80)
        let new = msgs(200...280)
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new),
            .fullReload
        )
    }

    func testDiffAtTheMutationCapStaysBatch() {
        // 40-row load-earlier page (the configured page size) must stay batch.
        let old = [LE] + msgs(41...60)
        let new = [LE] + msgs(1...60)
        guard case .batchDiff(let removals, let insertions) =
            ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new) else {
            return XCTFail("expected batchDiff for a page-sized prepend under a surviving header")
        }
        XCTAssertEqual(removals.count + insertions.count, 40)
        assertReplay(old: old, new: new)
    }

    // MARK: - Replay property

    /// Applying the plan's removals (old coordinates) then insertions (new
    /// coordinates, taking elements from `new`) must reproduce `new` exactly —
    /// this pins the NSTableView batch-contract correspondence.
    private func assertReplay(old: [String], new: [String], file: StaticString = #filePath, line: UInt = #line) {
        let plan = ChatTimelineReconcilePlanner.plan(oldIDs: old, newIDs: new)
        guard case .batchDiff(let removals, let insertions) = plan else {
            return XCTFail("expected batchDiff, got \(plan)", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(
            removals.count + insertions.count,
            ChatTimelineReconcilePlanner.maxBatchMutations,
            file: file,
            line: line
        )
        var replayed = old
        for offset in removals.sorted(by: >) {
            replayed.remove(at: offset)
        }
        for offset in insertions.sorted() {
            replayed.insert(new[offset], at: offset)
        }
        XCTAssertEqual(replayed, new, file: file, line: line)
    }
}
