enum AppShortcutSection: String, CaseIterable {
    case workspace
    case composer
    case conversation

    var title: String {
        rawValue.capitalized
    }

    var subtitle: String {
        switch self {
        case .workspace:
            return "Window and sidebar navigation."
        case .composer:
            return "Drafting and sending controls."
        case .conversation:
            return "Actions for the selected chat."
        }
    }
}

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case toggleChatList
    case searchChats
    case selectChats
    case selectAllChats
    case newChat
    case newAssistant
    case openAssistantSettings

    case focusComposer
    case openModelPicker
    case attachFiles
    case expandComposer
    case toggleComposerVisibility
    case stopGenerating

    case renameChat
    case toggleStarChat
    case deleteChat

    var id: String { rawValue }

    var section: AppShortcutSection {
        switch self {
        case .toggleChatList, .searchChats, .selectChats, .selectAllChats, .newChat, .newAssistant, .openAssistantSettings:
            return .workspace
        case .focusComposer, .openModelPicker, .attachFiles, .expandComposer, .toggleComposerVisibility, .stopGenerating:
            return .composer
        case .renameChat, .toggleStarChat, .deleteChat:
            return .conversation
        }
    }

    var title: String {
        switch self {
        case .toggleChatList:
            return "Toggle Chat List"
        case .searchChats:
            return "Search Chats"
        case .selectChats:
            return "Select Chats"
        case .selectAllChats:
            return "Select All Chats"
        case .newChat:
            return "New Chat"
        case .newAssistant:
            return "New Assistant"
        case .openAssistantSettings:
            return "Assistant Settings"
        case .focusComposer:
            return "Focus Composer"
        case .openModelPicker:
            return "Open Model Picker"
        case .attachFiles:
            return "Attach Files"
        case .expandComposer:
            return "Expand Composer"
        case .toggleComposerVisibility:
            return "Toggle Composer"
        case .stopGenerating:
            return "Stop Generating"
        case .renameChat:
            return "Rename Selected Chat"
        case .toggleStarChat:
            return "Star / Unstar Chat"
        case .deleteChat:
            return "Delete Selected Chat"
        }
    }

    var subtitle: String {
        switch self {
        case .toggleChatList:
            return "Show or hide the left chat sidebar."
        case .searchChats:
            return "Jump to the chat search field."
        case .selectChats:
            return "Turn multi-select on or off in the chat list, for batch delete and star."
        case .selectAllChats:
            return "Select every chat the list is currently showing (or deselect them again)."
        case .newChat:
            return "Create a new conversation."
        case .newAssistant:
            return "Create a new assistant profile."
        case .openAssistantSettings:
            return "Open the assistant inspector."
        case .focusComposer:
            return "Move focus to the message composer."
        case .openModelPicker:
            return "Open model and provider selection."
        case .attachFiles:
            return "Add files to the current draft."
        case .expandComposer:
            return "Open the full-size composer."
        case .toggleComposerVisibility:
            return "Show or hide the message composer."
        case .stopGenerating:
            return "Stop current generation (same as macOS cancel)."
        case .renameChat:
            return "Rename the currently selected chat."
        case .toggleStarChat:
            return "Mark or unmark the selected chat as starred."
        case .deleteChat:
            return "Delete the selected chat."
        }
    }

    var defaultBinding: AppShortcutBinding? {
        switch self {
        case .toggleChatList:
            return .command("b")
        case .searchChats:
            return .command("f")
        case .selectChats:
            return .command("l", modifiers: [.shift, .command])
        case .selectAllChats:
            // Deliberately not ⌘A: that is the system text Select All,
            // dispatched through the Edit menu to the first responder, so a
            // scene-level command claiming it would break selecting text in
            // the composer. Rebindable in Settings for anyone who wants it.
            return .command("a", modifiers: [.option, .command])
        case .newChat:
            return .command("n")
        case .newAssistant:
            return .command("n", modifiers: [.shift, .command])
        case .openAssistantSettings:
            return .command("i")
        case .focusComposer:
            return .command("k")
        case .openModelPicker:
            return .command("m", modifiers: [.shift, .command])
        case .attachFiles:
            return .command("a", modifiers: [.shift, .command])
        case .expandComposer:
            return .command("e", modifiers: [.shift, .command])
        case .toggleComposerVisibility:
            return .command("h", modifiers: [.shift, .command])
        case .stopGenerating:
            return .command(".")
        case .renameChat:
            return .command("r", modifiers: [.shift, .command])
        case .toggleStarChat:
            return .command("s", modifiers: [.shift, .command])
        case .deleteChat:
            return AppShortcutBinding(key: .delete, modifiers: [.command])
        }
    }
}
