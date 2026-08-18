import Foundation

/// Verb for in-flight chat chrome. One kind per visual cluster — never stack
/// three different orbs inside the same bubble.
enum JinActivityKind: String, CaseIterable, Sendable, Equatable {
    case listening
    case searching
    case solving
    case connecting
    case shaping
    case composing
    case thinking
    case working

    var accessibilityLabel: String {
        switch self {
        case .listening: return "Listening"
        case .searching: return "Searching"
        case .solving: return "Solving"
        case .connecting: return "Connecting"
        case .shaping: return "Shaping"
        case .composing: return "Composing"
        case .thinking: return "Thinking"
        case .working: return "Working"
        }
    }

    /// Quiet status copy next to an orb. Keep short; motion carries meaning.
    var statusLabel: String {
        switch self {
        case .listening: return "Listening"
        case .searching: return "Searching"
        case .solving: return "Solving"
        case .connecting: return "Connecting"
        case .shaping: return "Shaping"
        case .composing: return "Composing"
        case .thinking: return "Thinking"
        case .working: return "Generating"
        }
    }
}

/// Inputs for `JinActivityKind.resolve`. Pure data so tests do not need a
/// live `StreamingMessageState`.
struct JinActivitySnapshot: Equatable, Sendable {
    var isListening: Bool
    var hasRunningSearch: Bool
    var hasRunningCodeExecution: Bool
    var hasRunningTools: Bool
    var hasGeneratingMedia: Bool
    var hasVisibleText: Bool
    var isThinking: Bool
    var isBusy: Bool

    init(
        isListening: Bool = false,
        hasRunningSearch: Bool = false,
        hasRunningCodeExecution: Bool = false,
        hasRunningTools: Bool = false,
        hasGeneratingMedia: Bool = false,
        hasVisibleText: Bool = false,
        isThinking: Bool = false,
        isBusy: Bool = false
    ) {
        self.isListening = isListening
        self.hasRunningSearch = hasRunningSearch
        self.hasRunningCodeExecution = hasRunningCodeExecution
        self.hasRunningTools = hasRunningTools
        self.hasGeneratingMedia = hasGeneratingMedia
        self.hasVisibleText = hasVisibleText
        self.isThinking = isThinking
        self.isBusy = isBusy
    }

    var resolved: JinActivityKind? {
        JinActivityKind.resolve(self)
    }
}

extension JinActivityKind {
    /// Priority is top → bottom in the mapping table. Returns `nil` when
    /// nothing is happening so chrome can unmount (zero idle cost).
    static func resolve(_ snapshot: JinActivitySnapshot) -> JinActivityKind? {
        if snapshot.isListening { return .listening }
        if snapshot.hasRunningSearch { return .searching }
        if snapshot.hasRunningCodeExecution { return .solving }
        if snapshot.hasRunningTools { return .connecting }
        if snapshot.hasGeneratingMedia { return .shaping }
        if snapshot.hasVisibleText { return .composing }
        if snapshot.isThinking { return .thinking }
        if snapshot.isBusy { return .working }
        return nil
    }

    static func isThinkingActive(chunkCount: Int, isComplete: Bool) -> Bool {
        chunkCount > 0 && !isComplete
    }

    static func hasRunningSearch(_ activities: [SearchActivity]) -> Bool {
        activities.contains(where: SearchActivityTimelineSupport.isRunningActivity)
    }

    static func hasRunningCodeExecution(_ activities: [CodeExecutionActivity]) -> Bool {
        CodeExecutionTimelineSupport.hasActiveExecution(activities)
    }

    static func hasRunningTools(
        toolCalls: [ToolCall],
        resultsByCallID: [String: ToolResult]
    ) -> Bool {
        toolCalls.contains { resultsByCallID[$0.id] == nil }
    }

    /// Live verb for the streaming bubble header. One orb for the whole turn
    /// so thinking / search / tools do not remount a new representable.
    static func resolveStreaming(
        searchActivities: [SearchActivity],
        codeExecutionActivities: [CodeExecutionActivity],
        toolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult],
        artifactCount: Int,
        hasVisibleText: Bool,
        thinkingChunkCount: Int,
        isThinkingComplete: Bool
    ) -> JinActivityKind {
        resolve(
            JinActivitySnapshot(
                hasRunningSearch: hasRunningSearch(searchActivities),
                hasRunningCodeExecution: hasRunningCodeExecution(codeExecutionActivities),
                hasRunningTools: hasRunningTools(
                    toolCalls: toolCalls,
                    resultsByCallID: toolResultsByCallID
                ),
                hasGeneratingMedia: artifactCount > 0 && !hasVisibleText,
                hasVisibleText: hasVisibleText,
                isThinking: isThinkingActive(
                    chunkCount: thinkingChunkCount,
                    isComplete: isThinkingComplete
                ),
                isBusy: true
            )
        ) ?? .working
    }
}
