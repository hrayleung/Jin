import Foundation

/// Canonical top-to-bottom order for assistant bubble body sections.
///
/// Streaming and persisted rows must share this stack. MCP tool cards
/// (including TinyFish `search` / `fetch_content`) used to render *above*
/// the prose while streaming and *below* it after persist, so the card
/// jumped as soon as the turn landed in `MessageRow`.
enum ChatAssistantBubbleStackSupport {
    enum Section: String, CaseIterable, Equatable {
        case searchActivities
        case codeExecution
        case thinking
        case text
        case artifacts
        case mcpTools
    }

    static let order: [Section] = [
        .searchActivities,
        .codeExecution,
        .thinking,
        .text,
        .artifacts,
        .mcpTools
    ]

    struct Presence: Equatable {
        var hasSearchActivities = false
        var hasCodeExecution = false
        var hasThinking = false
        var hasText = false
        var hasArtifacts = false
        var hasMCPTools = false
    }

    static func visibleSections(in presence: Presence) -> [Section] {
        order.filter { section in
            switch section {
            case .searchActivities: return presence.hasSearchActivities
            case .codeExecution: return presence.hasCodeExecution
            case .thinking: return presence.hasThinking
            case .text: return presence.hasText
            case .artifacts: return presence.hasArtifacts
            case .mcpTools: return presence.hasMCPTools
            }
        }
    }
}
