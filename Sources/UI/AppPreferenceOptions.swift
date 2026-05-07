enum NewChatModelMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Specific Model"
        case .lastUsed: return "Use Last Used Model"
        }
    }
}

enum NewChatMCPMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Custom Defaults"
        case .lastUsed: return "Use Last Chat's MCP"
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

enum ChatNamingMode: String, CaseIterable, Identifiable {
    case firstRoundFixed
    case everyRound

    var id: String { rawValue }

    var label: String {
        switch self {
        case .firstRoundFixed:
            return "First Round Only"
        case .everyRound:
            return "Rename Every Round"
        }
    }
}

enum ThinkingBlockDisplayMode: String, CaseIterable, Identifiable {
    case expanded
    case collapseOnComplete
    case alwaysCollapsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expanded: return "Always Expanded"
        case .collapseOnComplete: return "Collapse After Response"
        case .alwaysCollapsed: return "Always Collapsed"
        }
    }

    var description: String {
        switch self {
        case .expanded:
            return "Thinking blocks stay expanded at all times. You can still collapse them manually."
        case .collapseOnComplete:
            return "Thinking blocks are expanded during streaming and automatically collapsed once the response finishes."
        case .alwaysCollapsed:
            return "Thinking blocks are collapsed during streaming and after completion. A subtle animation indicates active thinking. Click to expand at any time."
        }
    }

    /// Whether thinking content should start expanded for completed (non-streaming) messages.
    var startsExpandedOnComplete: Bool {
        self == .expanded
    }

    /// Whether thinking content should start expanded during streaming.
    var startsExpandedDuringStreaming: Bool {
        self != .alwaysCollapsed
    }
}

enum CodeBlockDisplayMode: String, CaseIterable, Identifiable {
    case expanded
    case collapsible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expanded: return "Always Expanded"
        case .collapsible: return "Smart Fold Long Blocks"
        }
    }

    var description: String {
        switch self {
        case .expanded:
            return "Code blocks always show their full content."
        case .collapsible:
            return "Only long code blocks start condensed, with a fade and a simple Show more control."
        }
    }
}

enum GeneralSettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case chat
    case shortcuts
    case defaults
    case updates
    case data

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .chat: return "Chat"
        case .shortcuts: return "Keyboard Shortcuts"
        case .defaults: return "Defaults"
        case .updates: return "Updates"
        case .data: return "Data"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "textformat"
        case .chat: return "bubble.left.and.bubble.right"
        case .shortcuts: return "command"
        case .defaults: return "sparkles"
        case .updates: return "arrow.triangle.2.circlepath"
        case .data: return "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "Theme, fonts, and content display modes."
        case .chat: return "Send behavior, network trace, and notifications."
        case .shortcuts: return "Show and customize keyboard shortcuts."
        case .defaults: return "Model and MCP defaults for new chats."
        case .updates: return "Automatic updates and pre-release channel."
        case .data: return "Storage usage, cache management, and local data."
        }
    }
}
