import Foundation
import SwiftUI

/// Bridge between the SwiftUI minimap rail and the AppKit transcript
/// controller, in the same shape as `ChatTimelineScrollHandle`: the rail talks
/// to this object, the object holds a weak controller reference, and the
/// controller never leaks into the view tree.
///
/// It exists as its own `ObservableObject` because
/// `ChatSingleThreadMessagesContentView` is `EquatableView`-gated on
/// `ChatStageEquatableKey` — scroll-frequency state must never travel through
/// that key or the whole transcript would re-render as the user scrolls.
@MainActor
final class ChatConversationMinimapModel: ObservableObject {
    weak var controller: ChatTimelineTableController?

    /// The message currently at the top of the viewport. The rail maps it to a
    /// turn to draw the "you are here" tick.
    ///
    /// Fed from the controller's `boundsDidChange`, which fires many times a
    /// second while streaming, so the setter publishes **only on change** —
    /// the same discipline as the existing `if pinned != isPinned` guard.
    @Published private(set) var activeMessageID: UUID?

    /// A jump whose target row is not in the render window yet. Deliberately
    /// **not** `@Published`: it is written while SwiftUI is applying the
    /// `messageRenderLimit` change that will bring the row in, and publishing
    /// from inside a view update is exactly what triggers the
    /// "Publishing changes from within view updates" warning.
    private var pendingJumpID: UUID?

    func reportTopVisibleMessageID(_ id: UUID?) {
        guard activeMessageID != id else { return }
        activeMessageID = id
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
    /// Unanimated: the row set just changed wholesale (a "Load earlier"-shaped
    /// prepend of every message before the target), and animating a jump of
    /// that size across freshly estimated heights reads as a glitch.
    func timelineDidApplyRows() {
        guard let target = pendingJumpID,
              let controller,
              controller.canScroll(to: target) else { return }
        pendingJumpID = nil
        controller.scrollTo(messageID: target, animated: false)
    }
}
