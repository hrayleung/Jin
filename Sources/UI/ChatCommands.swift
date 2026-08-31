import SwiftUI

struct ChatCommands: Commands {
    @FocusedValue(\.chatActions) private var chatActions
    @FocusedValue(\.workspaceActions) private var workspaceActions
    @FocusedValue(\.chatSelectionActions) private var chatSelectionActions
    @ObservedObject var shortcutsStore: AppShortcutsStore

    var body: some Commands {
        CommandMenu("Chat") {
            workspaceSection
            Divider()
            composerSection
            Divider()
            conversationSection
        }
    }

    @ViewBuilder
    private var workspaceSection: some View {
        Button(workspaceActions?.isSidebarVisible == true ? "Hide Chat List" : "Show Chat List") {
            workspaceActions?.toggleSidebar()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .toggleChatList))
        .disabled(workspaceActions == nil)

        Button("Search Chats") {
            workspaceActions?.focusChatSearch()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .searchChats))
        .disabled(workspaceActions == nil)

        Button(workspaceActions?.isChatSelectionModeActive == true ? "Done Selecting Chats" : "Select Chats") {
            workspaceActions?.toggleChatSelectionMode()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .selectChats))
        .disabled(workspaceActions == nil)

        Button(chatSelectionActions?.allVisibleSelected == true ? "Deselect All Chats" : "Select All Chats") {
            chatSelectionActions?.selectAllChats()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .selectAllChats))
        .disabled(chatSelectionActions?.hasVisibleChats != true)

        Button("New Chat") {
            workspaceActions?.createNewChat()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newChat))
        .disabled(workspaceActions == nil)

        Button("New Assistant") {
            workspaceActions?.createAssistant()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newAssistant))
        .disabled(workspaceActions == nil)

        Button("Assistant Settings") {
            workspaceActions?.openAssistantSettings()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .openAssistantSettings))
        .disabled(workspaceActions == nil)
    }

    @ViewBuilder
    private var composerSection: some View {
        Button("Focus Composer") {
            chatActions?.focusComposer()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .focusComposer))
        .disabled(chatActions == nil)

        Button("Model Picker…") {
            chatActions?.openModelPicker()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .openModelPicker))
        .disabled(chatActions == nil)

        Button("Attach…") {
            chatActions?.attach()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .attachFiles))
        .disabled(!(chatActions?.canAttach ?? false))

        Button("Expand Composer") {
            chatActions?.toggleExpandedComposer()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .expandComposer))
        .disabled(chatActions == nil)

        Button(chatActions?.isComposerHidden == true ? "Show Composer" : "Hide Composer") {
            chatActions?.toggleComposerVisibility()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .toggleComposerVisibility))
        .disabled(chatActions == nil)

        Button("Stop Generating") {
            chatActions?.stopStreaming()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .stopGenerating))
        .disabled(!(chatActions?.canStopStreaming ?? false))
    }

    /// How many chats the delete command would remove. A multi-selection wins;
    /// otherwise it's the open chat, if there is one.
    private var deletableChatCount: Int {
        if let chatSelectionActions, chatSelectionActions.hasExplicitSelection {
            return chatSelectionActions.selectedCount
        }
        return (workspaceActions?.canDeleteSelectedChat ?? false) ? 1 : 0
    }

    @ViewBuilder
    private var conversationSection: some View {
        Button("Rename Chat") {
            workspaceActions?.renameSelectedChat()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .renameChat))
        .disabled(!(workspaceActions?.canRenameSelectedChat ?? false))

        Button(workspaceActions?.selectedChatIsStarred == true ? "Unstar Chat" : "Star Chat") {
            workspaceActions?.toggleSelectedChatStar()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .toggleStarChat))
        .disabled(!(workspaceActions?.canToggleSelectedChatStar ?? false))

        // One key for both shapes: with a multi-selection it takes the whole
        // set, otherwise it falls back to the chat that's open.
        Button(ChatsSidebarSelectionSupport.deleteTitle(count: deletableChatCount), role: .destructive) {
            if let chatSelectionActions, chatSelectionActions.hasExplicitSelection {
                chatSelectionActions.deleteSelectedChats()
            } else {
                workspaceActions?.deleteSelectedChat()
            }
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .deleteChat))
        .disabled(deletableChatCount == 0)
    }
}
