import SwiftUI

struct ChatCommands: Commands {
    @FocusedValue(\.chatActions) private var chatActions
    @FocusedValue(\.workspaceActions) private var workspaceActions
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

        Button("Stop Generating") {
            chatActions?.stopStreaming()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .stopGenerating))
        .disabled(!(chatActions?.canStopStreaming ?? false))
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

        Button("Delete Chat", role: .destructive) {
            workspaceActions?.deleteSelectedChat()
        }
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .deleteChat))
        .disabled(!(workspaceActions?.canDeleteSelectedChat ?? false))
    }
}
