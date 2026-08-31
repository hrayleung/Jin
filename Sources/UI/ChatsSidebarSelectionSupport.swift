import Foundation

/// Selection arithmetic for the chats sidebar.
///
/// The sidebar drives two selection models at once: the single conversation
/// that is open in the detail pane, and the set of conversations a batch
/// action (delete / star) applies to. Keeping the rules here — instead of
/// inline in the `List` binding — makes them testable without a SwiftData
/// stack and keeps the view free of one-off conditionals.
enum ChatsSidebarSelectionSupport {

    /// What the detail pane should do after the `List` reports a new selection.
    enum OpenAction: Equatable {
        /// Open this conversation in the detail pane.
        case open(UUID)
        /// The user deselected everything — close the detail pane.
        case clear
        /// Leave the detail pane on whatever is already open.
        case keep
    }

    /// Maps a set reported by the sidebar `List` onto the open conversation.
    ///
    /// - Two or more rows means the user is assembling a batch selection
    ///   (⌘-click / ⇧-click), so the open conversation must not change under
    ///   them.
    /// - An empty set coming from a conversation the list doesn't contain is
    ///   the `List` reconciling a tag it can't find. That is the normal state
    ///   for a brand-new chat: it has no messages yet, so it has no row.
    ///   Clearing there would close the chat the user just created.
    static func openAction(
        newSelection: Set<UUID>,
        openConversationID: UUID?,
        openConversationIsListed: Bool
    ) -> OpenAction {
        if newSelection.count == 1, let id = newSelection.first {
            return id == openConversationID ? .keep : .open(id)
        }

        guard newSelection.isEmpty else { return .keep }
        guard openConversationID != nil, openConversationIsListed else { return .keep }
        return .clear
    }

    /// Rows the sidebar `List` should highlight.
    ///
    /// With no explicit multi-selection the highlight tracks the open
    /// conversation, which is exactly what the pre-batch single-selection
    /// sidebar did.
    static func highlightedIDs(
        explicitSelection: Set<UUID>,
        openConversationID: UUID?,
        openConversationIsListed: Bool
    ) -> Set<UUID> {
        guard explicitSelection.isEmpty else { return explicitSelection }
        guard let openConversationID, openConversationIsListed else { return [] }
        return [openConversationID]
    }

    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    /// ⇧-click range selection, in the order the rows are displayed.
    /// Returns `nil` when there is no usable anchor, so the caller can fall
    /// back to a plain toggle.
    static func rangeSelection(
        from anchorID: UUID?,
        to targetID: UUID,
        in orderedIDs: [UUID]
    ) -> Set<UUID>? {
        guard let anchorID,
              let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID) else { return nil }

        let bounds = anchorIndex <= targetIndex
            ? anchorIndex...targetIndex
            : targetIndex...anchorIndex
        return Set(orderedIDs[bounds])
    }

    /// "Select All" adds every currently visible row; once they're all in, the
    /// same button removes them. Rows hidden by the search filter keep their
    /// state either way, so filtering never silently drops a selection.
    static func selectAllToggled(_ selection: Set<UUID>, visibleIDs: [UUID]) -> Set<UUID> {
        let visible = Set(visibleIDs)
        guard !visible.isEmpty else { return selection }
        if visible.isSubset(of: selection) {
            return selection.subtracting(visible)
        }
        return selection.union(visible)
    }

    static func allVisibleSelected(_ selection: Set<UUID>, visibleIDs: [UUID]) -> Bool {
        guard !visibleIDs.isEmpty else { return false }
        return Set(visibleIDs).isSubset(of: selection)
    }

    /// One button drives both directions: anything unstarred in the selection
    /// means "star them all"; only an entirely starred selection unstars.
    static func shouldStarSelection(starredFlags: [Bool]) -> Bool {
        starredFlags.contains(false) || starredFlags.isEmpty
    }

    /// Preserves the display order of `ordered` while filtering to `ids`, and
    /// drops IDs whose conversation no longer exists.
    static func orderedSelection<Element>(
        from ordered: [Element],
        matching ids: Set<UUID>,
        id: (Element) -> UUID
    ) -> [Element] {
        guard !ids.isEmpty else { return [] }
        return ordered.filter { ids.contains(id($0)) }
    }

    // MARK: - Copy

    static func selectionSummary(count: Int) -> String {
        count == 1 ? "1 selected" : "\(count) selected"
    }

    static func deleteTitle(count: Int) -> String {
        count == 1 ? "Delete Chat" : "Delete \(count) Chats"
    }

    static func starTitle(shouldStar: Bool, count: Int) -> String {
        let noun = count == 1 ? "Chat" : "\(count) Chats"
        return shouldStar ? "Star \(noun)" : "Unstar \(noun)"
    }

    static func deleteConfirmationTitle(count: Int) -> String {
        count == 1 ? "Delete chat?" : "Delete \(count) chats?"
    }

    static func deleteConfirmationMessage(titles: [String]) -> String {
        guard titles.count > 1 else {
            return "This will permanently delete \u{201C}\(titles.first ?? "")\u{201D}."
        }
        guard titles.count > 3 else {
            let quoted = titles.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
            return "This will permanently delete \(quoted)."
        }
        return "This will permanently delete \(titles.count) chats."
    }
}
