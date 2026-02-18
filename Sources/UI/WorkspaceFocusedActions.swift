import SwiftUI

struct WorkspaceFocusedActions {
    let isSidebarVisible: Bool
    let canRenameSelectedChat: Bool
    let canToggleSelectedChatStar: Bool
    let canDeleteSelectedChat: Bool
    let selectedChatIsStarred: Bool
    let toggleSidebar: () -> Void
    let focusChatSearch: () -> Void
    let createNewChat: () -> Void
    let createAssistant: () -> Void
    let openAssistantSettings: () -> Void
    let renameSelectedChat: () -> Void
    let toggleSelectedChatStar: () -> Void
    let deleteSelectedChat: () -> Void
}

private struct WorkspaceFocusedActionsKey: FocusedValueKey {
    typealias Value = WorkspaceFocusedActions
}

extension FocusedValues {
    var workspaceActions: WorkspaceFocusedActions? {
        get { self[WorkspaceFocusedActionsKey.self] }
        set { self[WorkspaceFocusedActionsKey.self] = newValue }
    }
}
