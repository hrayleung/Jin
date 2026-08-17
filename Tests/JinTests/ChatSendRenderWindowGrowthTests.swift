import XCTest
@testable import Jin

/// The send path grows `messageRenderLimit` so an outgoing message does not
/// *slide* the suffix window (drop the oldest visible identity while appending
/// a new one), because that slide reconciles as removal+insertion and used to
/// flash the stage.
///
/// The growth has to be incremental. Jumping the limit to the whole
/// conversation also stops the slide, but replaces it with something worse: the
/// entire backlog is inserted at the head in a single apply, which exceeds
/// `ChatTimelineReconcilePlanner.maxBatchMutations` and degrades to a full
/// `reloadData` — every realized cell torn down and rebuilt on the Enter
/// keypress, in the one conversation shape where that costs the most.
final class ChatSendRenderWindowGrowthTests: XCTestCase {

    private let initialLimit = 24

    private func messageIDs(_ count: Int) -> [String] {
        (0..<count).map { "msg-\($0)" }
    }

    /// Rows as `ChatSingleThreadMessagesContentView` builds them: an optional
    /// "load earlier" header, the windowed suffix, then the streaming row.
    private func rowIdentities(
        allMessages: [String],
        renderLimit: Int,
        includeStreamingRow: Bool
    ) -> [String] {
        let visible = Array(allMessages.suffix(renderLimit))
        var rows: [String] = []
        if allMessages.count - visible.count > 0 {
            rows.append("loadEarlier")
        }
        rows.append(contentsOf: visible)
        if includeStreamingRow {
            rows.append("streaming")
        }
        return rows
    }

    func testGrowsByExactlyTheAppendedCount() {
        XCTAssertEqual(
            ChatMessageStagePresentationSupport.renderLimitAfterAppend(
                currentLimit: initialLimit,
                projectedTotal: 101,
                appended: 1
            ),
            25
        )
    }

    func testClampsToTheProjectedTotalAndNeverShrinks() {
        // A short conversation cannot need a window wider than itself.
        XCTAssertEqual(
            ChatMessageStagePresentationSupport.renderLimitAfterAppend(
                currentLimit: 4,
                projectedTotal: 5,
                appended: 3
            ),
            5
        )
        // An already-wide window (load-earlier paging, minimap jump) stays wide.
        XCTAssertEqual(
            ChatMessageStagePresentationSupport.renderLimitAfterAppend(
                currentLimit: 200,
                projectedTotal: 50,
                appended: 1
            ),
            200
        )
        // Arming the streaming placeholder appends no message.
        XCTAssertEqual(
            ChatMessageStagePresentationSupport.renderLimitAfterAppend(
                currentLimit: initialLimit,
                projectedTotal: 101,
                appended: 0
            ),
            initialLimit
        )
    }

    /// The behaviour that matters: first send in a long chat is a pure tail
    /// insert, so every already-realized cell survives.
    func testFirstSendInLongChatReconcilesAsAppendTail() {
        let existing = messageIDs(100)
        let oldIDs = rowIdentities(
            allMessages: existing,
            renderLimit: initialLimit,
            includeStreamingRow: false
        )

        let afterSend = existing + ["msg-100"]
        let grownLimit = ChatMessageStagePresentationSupport.renderLimitAfterAppend(
            currentLimit: initialLimit,
            projectedTotal: afterSend.count,
            appended: 1
        )
        let newIDs = rowIdentities(
            allMessages: afterSend,
            renderLimit: grownLimit,
            includeStreamingRow: true
        )

        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: oldIDs, newIDs: newIDs),
            .appendTail(inserted: oldIDs.count..<newIDs.count)
        )
    }

    /// Documents the regression this replaced: widening to the full history put
    /// the diff past `maxBatchMutations`, so the planner fell back to
    /// `fullReload`.
    func testWideningToTheWholeConversationWouldFullReload() {
        let existing = messageIDs(100)
        let oldIDs = rowIdentities(
            allMessages: existing,
            renderLimit: initialLimit,
            includeStreamingRow: false
        )

        let afterSend = existing + ["msg-100"]
        // The old rule: max(cachedTotal, messages.count) + appended + 1 spare.
        let previousRuleLimit = existing.count + 1 + 1
        let newIDs = rowIdentities(
            allMessages: afterSend,
            renderLimit: previousRuleLimit,
            includeStreamingRow: true
        )

        XCTAssertEqual(ChatTimelineReconcilePlanner.plan(oldIDs: oldIDs, newIDs: newIDs), .fullReload)
    }

    /// Persisting the assistant reply appends another visible row; without
    /// matching growth the window would simply slide one turn later.
    func testStreamEndKeepsTheWindowAnchored() {
        let existing = messageIDs(100)
        let afterUserSend = existing + ["msg-100"]
        let limitAfterSend = ChatMessageStagePresentationSupport.renderLimitAfterAppend(
            currentLimit: initialLimit,
            projectedTotal: afterUserSend.count,
            appended: 1
        )
        let oldIDs = rowIdentities(
            allMessages: afterUserSend,
            renderLimit: limitAfterSend,
            includeStreamingRow: true
        )

        let afterReply = afterUserSend + ["msg-101"]
        let limitAfterReply = ChatMessageStagePresentationSupport.renderLimitAfterAppend(
            currentLimit: limitAfterSend,
            projectedTotal: afterReply.count,
            appended: 1
        )
        let newIDs = rowIdentities(
            allMessages: afterReply,
            renderLimit: limitAfterReply,
            includeStreamingRow: false
        )

        // Streaming row replaced in place by the persisted assistant row: same
        // count, one differing identity — the cheapest non-identical plan.
        XCTAssertEqual(oldIDs.count, newIDs.count)
        XCTAssertEqual(
            ChatTimelineReconcilePlanner.plan(oldIDs: oldIDs, newIDs: newIDs),
            .reloadInPlace(changed: IndexSet(integer: newIDs.count - 1))
        )
    }
}
