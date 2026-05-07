import SwiftUI

// MARK: - Root Presentations

extension ContentView {

    func contentPresentations<Content: View>(_ content: Content) -> some View {
        content
            .task {
                bootstrapDefaultProvidersIfNeeded()
                bootstrapDefaultAssistantsIfNeeded()
                await updateManager.checkForUpdatesOnLaunchIfNeeded()
            }
            .sheet(isPresented: $isAssistantInspectorPresented) {
                if let selectedAssistant {
                    AssistantInspectorView(assistant: selectedAssistant)
                }
            }
            .confirmationDialog(
                "Delete assistant?",
                isPresented: $showingDeleteAssistantConfirmation,
                presenting: assistantPendingDeletion
            ) { assistant in
                Button("Delete", role: .destructive) { deleteAssistant(assistant) }
            } message: { assistant in
                Text("This will permanently delete \u{201C}\(assistant.displayName)\u{201D} and all of its chats.")
            }
            .confirmationDialog(
                "Delete chat?",
                isPresented: $showingDeleteConversationConfirmation,
                presenting: conversationPendingDeletion
            ) { conversation in
                Button("Delete", role: .destructive) { deleteConversation(conversation) }
            } message: { conversation in
                Text("This will permanently delete \u{201C}\(conversation.title)\u{201D}.")
            }
            .alert("Rename Chat", isPresented: $showingRenameConversationAlert, presenting: conversationPendingRename) { _ in
                TextField("Chat title", text: $renameConversationDraftTitle)
                Button("Cancel", role: .cancel) { conversationPendingRename = nil }
                Button("Save") { applyManualConversationRename() }
                    .disabled(!ConversationRenameSupport.canSaveTitle(renameConversationDraftTitle))
            } message: { _ in
                Text("Enter a new title for this chat.")
            }
            .alert("Title Regeneration Failed", isPresented: $showingTitleRegenerationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(titleRegenerationErrorMessage)
            }
            .focusedSceneValue(\.workspaceActions, workspaceFocusedActions)
    }

    var workspaceFocusedActions: WorkspaceFocusedActions {
        WorkspaceFocusedActions(
            isSidebarVisible: isSidebarVisible,
            canRenameSelectedChat: selectedConversation != nil,
            canToggleSelectedChatStar: selectedConversation != nil,
            canDeleteSelectedChat: selectedConversation != nil,
            selectedChatIsStarred: selectedConversation?.isStarred == true,
            toggleSidebar: toggleSidebarVisibility,
            focusChatSearch: focusChatSearch,
            createNewChat: createNewConversation,
            createAssistant: createAssistant,
            openAssistantSettings: openAssistantSettings,
            renameSelectedChat: requestRenameSelectedConversation,
            toggleSelectedChatStar: toggleSelectedConversationStar,
            deleteSelectedChat: requestDeleteSelectedConversation
        )
    }
}
