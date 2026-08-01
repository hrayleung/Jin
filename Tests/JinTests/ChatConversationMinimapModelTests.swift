import Combine
import XCTest
@testable import Jin

/// The rail's bridge to the transcript controller. These cover the two rules
/// that are easy to get wrong and impossible to see in a screenshot: a parked
/// jump must never outlive one row-apply (it suppresses follow-to-bottom while
/// it lives), and scroll-position reports must not publish unless the value
/// actually changed (the controller feeds them at streaming frequency).
@MainActor
final class ChatConversationMinimapModelTests: XCTestCase {

    // MARK: - Parked jumps

    func testJumpParksWhenTheRowIsNotLoadedYet() {
        let model = ChatConversationMinimapModel()
        XCTAssertFalse(model.hasPendingJump)

        // No controller attached stands in for "the target row isn't in the
        // render window yet" — both leave the jump waiting.
        model.jump(to: UUID())

        XCTAssertTrue(model.hasPendingJump, "follow-to-bottom stays suppressed until this lands")
    }

    func testParkedJumpIsClearedByTheNextRowApplyEvenIfUnreachable() {
        let model = ChatConversationMinimapModel()
        model.jump(to: UUID())

        model.timelineDidApplyRows()

        XCTAssertFalse(
            model.hasPendingJump,
            "a jump whose target never arrives (deleted message) must not suppress follow-to-bottom forever"
        )
    }

    func testForcedBottomScrollCancelsAParkedJump() {
        let model = ChatConversationMinimapModel()
        model.jump(to: UUID())

        model.cancelPendingJump()

        XCTAssertFalse(model.hasPendingJump)
    }

    // MARK: - Position reporting

    func testActiveMessageIsPublishedOnlyWhenItChanges() {
        let model = ChatConversationMinimapModel()
        var publishCount = 0
        let subscription = model.railState.objectWillChange.sink { _ in publishCount += 1 }
        defer { subscription.cancel() }

        let first = UUID()
        model.reportTopVisibleMessageID(first)
        model.reportTopVisibleMessageID(first)
        model.reportTopVisibleMessageID(first)

        XCTAssertEqual(model.activeMessageID, first)
        XCTAssertEqual(publishCount, 1, "repeat reports during a scroll must not re-render the rail")

        model.reportTopVisibleMessageID(UUID())
        XCTAssertEqual(publishCount, 2)

        model.reportTopVisibleMessageID(nil)
        XCTAssertEqual(publishCount, 3)
        XCTAssertNil(model.activeMessageID)
    }

    func testScrollReportsNeverPublishOnTheOuterModel() {
        // The stage view owns the model as @StateObject, which subscribes to
        // objectWillChange unconditionally — one publish here re-renders the
        // whole transcript per message-boundary crossing. Scroll-frequency
        // state must publish only on railState.
        let model = ChatConversationMinimapModel()
        var outerPublishes = 0
        let subscription = model.objectWillChange.sink { _ in outerPublishes += 1 }
        defer { subscription.cancel() }

        model.reportTopVisibleMessageID(UUID())
        model.reportTopVisibleMessageID(nil)
        model.jump(to: UUID())
        model.timelineDidApplyRows()
        model.cancelPendingJump()

        XCTAssertEqual(outerPublishes, 0, "the transcript-owning @StateObject must never be invalidated by scroll traffic")
    }
}
