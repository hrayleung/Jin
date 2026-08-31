import SwiftUI

/// Batch actions for the chat list, published by `ChatsSidebarSectionView`.
///
/// The selected set deliberately lives in that subview so ⌘-clicking a second
/// row doesn't re-evaluate `ChatView`. Routing it up through `ContentView`
/// just to reach the menu bar would undo that, so the sidebar publishes a
/// scene value instead and `ChatCommands` reads it directly.
struct ChatSelectionFocusedActions {
    /// Chats a batch action would apply to right now. With no explicit
    /// multi-selection this is the open chat, so it's 1 in the common case.
    let selectedCount: Int
    /// The user actually picked these rows, rather than this being the
    /// open-chat fallback. Deleting one *checked* row must remove that row,
    /// not whatever happens to be open in the detail pane.
    let hasExplicitSelection: Bool
    let hasVisibleChats: Bool
    let allVisibleSelected: Bool
    let selectAllChats: () -> Void
    let deleteSelectedChats: () -> Void
}

private struct ChatSelectionFocusedActionsKey: FocusedValueKey {
    typealias Value = ChatSelectionFocusedActions
}

extension FocusedValues {
    var chatSelectionActions: ChatSelectionFocusedActions? {
        get { self[ChatSelectionFocusedActionsKey.self] }
        set { self[ChatSelectionFocusedActionsKey.self] = newValue }
    }
}
