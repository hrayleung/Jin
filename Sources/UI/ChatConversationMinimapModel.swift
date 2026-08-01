import Foundation
import SwiftUI

/// Scroll-frequency state, observed ONLY by the rail. It is split out of
/// `ChatConversationMinimapModel` because the stage view owns that model as
/// `@StateObject`, and `@StateObject` subscribes the owning view to
/// `objectWillChange` unconditionally — one publish there re-renders the
/// entire transcript per message-boundary crossing, which is exactly what
/// the model's contract forbids.
@MainActor
final class ChatConversationMinimapRailState: ObservableObject {
    /// The message currently at the top of the viewport. The rail maps it to a
    /// turn to draw the "you are here" tick.
    ///
    /// Fed from the controller's `boundsDidChange`, which fires many times a
    /// second while streaming, so the setter publishes **only on change** —
    /// the same discipline as the existing `if pinned != isPinned` guard.
    @Published private(set) var activeMessageID: UUID?

    func reportTopVisibleMessageID(_ id: UUID?) {
        guard activeMessageID != id else { return }
        activeMessageID = id
    }
}

/// Bridge between the SwiftUI minimap rail and the AppKit transcript
/// controller, in the same shape as `ChatTimelineScrollHandle`: the rail talks
/// to this object, the object holds a weak controller reference, and the
/// controller never leaks into the view tree.
///
/// It exists as its own `ObservableObject` because
/// `ChatSingleThreadMessagesContentView` is `EquatableView`-gated on
/// `ChatStageEquatableKey` — scroll-frequency state must never travel through
/// that key or the whole transcript would re-render as the user scrolls.
///
/// INVARIANT: this object must never publish. The stage view holds it as
/// `@StateObject`, so a single `objectWillChange` here re-renders the whole
/// transcript. Scroll-frequency state lives on `railState` (observed only by
/// the rail); `controller` and `pendingJumpID` stay plain vars.
@MainActor
final class ChatConversationMinimapModel: ObservableObject {
    weak var controller: ChatTimelineTableController?

    /// Rail-only observable state; see `ChatConversationMinimapRailState`.
    let railState = ChatConversationMinimapRailState()

    /// Read-only convenience mirroring `railState.activeMessageID`.
    var activeMessageID: UUID? { railState.activeMessageID }

    /// A jump whose target row is not in the render window yet. Deliberately
    /// **not** `@Published`: it is written while SwiftUI is applying the
    /// `messageRenderLimit` change that will bring the row in, and publishing
    /// from inside a view update is exactly what triggers the
    /// "Publishing changes from within view updates" warning.
    private var pendingJumpID: UUID?

    /// While a jump is parked the transcript must not follow to the bottom:
    /// widening the render window is a wholesale row change, and the pinned
    /// re-anchor would flash the viewport to the newest message a beat before
    /// the jump lands on the turn the user actually asked for.
    var hasPendingJump: Bool { pendingJumpID != nil }

    /// An explicit bottom-scroll (the chevron, opening a conversation)
    /// supersedes a jump that hasn't landed.
    func cancelPendingJump() {
        pendingJumpID = nil
    }

    func reportTopVisibleMessageID(_ id: UUID?) {
        railState.reportTopVisibleMessageID(id)
    }

    /// Scrolls the transcript to `messageID`, or parks the request until the
    /// row exists. The caller raises `messageRenderLimit` first, so a parked
    /// jump is resolved by the very next `apply(_:)`.
    func jump(to messageID: UUID) {
        if let controller, controller.canScroll(to: messageID) {
            pendingJumpID = nil
            controller.scrollTo(messageID: messageID, animated: true)
            return
        }
        pendingJumpID = messageID
    }

    /// Controller hook, invoked after the table applies a new row set.
    /// Completes a jump that was waiting for its row to enter the window.
    ///
    /// One shot: the caller raises `messageRenderLimit` in the same turn as
    /// `jump(to:)`, so the very next `apply(_:)` already carries the row. The
    /// request is therefore cleared whether or not it can be honoured — a jump
    /// left parked forever (target message since deleted) would keep
    /// `hasPendingJump` true and permanently suppress follow-to-bottom.
    ///
    /// Unanimated: the row set just changed wholesale (a prepend of every
    /// message before the target), and animating a jump of that size across
    /// freshly estimated heights reads as a glitch.
    func timelineDidApplyRows() {
        guard let target = pendingJumpID else { return }
        pendingJumpID = nil
        guard let controller, controller.canScroll(to: target) else { return }
        controller.scrollTo(messageID: target, animated: false)
    }
}
