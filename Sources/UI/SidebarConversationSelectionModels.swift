import Foundation

/// Everything a sidebar chat row needs to know about the current selection.
/// Passed as one value so the row's parameter list stays readable and so the
/// parent computes the batch-wide facts (count, star direction) once per body
/// pass instead of once per row.
struct SidebarConversationSelectionState: Equatable {
    /// Explicit selection mode: rows show a checkbox and a click toggles it
    /// instead of opening the chat.
    var isSelectionModeActive: Bool
    /// This row is part of the current selection.
    var isSelected: Bool
    /// How many chats a batch action would apply to right now.
    var batchCount: Int
    /// Direction the batch star action would take (see
    /// `ChatsSidebarSelectionSupport.shouldStarSelection`).
    var shouldStarBatch: Bool

    /// A context-menu action on this row applies to the whole selection only
    /// when the row is actually part of a multi-selection. Right-clicking an
    /// unselected row keeps the single-chat menu, matching AppKit.
    var appliesToBatch: Bool {
        isSelected && batchCount > 1
    }
}

/// Selection callbacks a sidebar chat row can raise. Grouped for the same
/// reason as `SidebarConversationSelectionState`.
struct SidebarConversationSelectionActions {
    /// `extendingRange` is true for a ⇧-click in selection mode.
    var toggle: (_ extendingRange: Bool) -> Void
    /// Enter selection mode with this row already checked.
    var beginSelection: () -> Void
    var batchStar: () -> Void
    var batchDelete: () -> Void
    var clearSelection: () -> Void
}
