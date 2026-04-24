import Foundation

struct MessageRenderItem: Identifiable, Sendable {
    let id: UUID
    let contextThreadID: UUID?
    let role: String
    let timestamp: Date
    let renderedBlocks: [RenderedMessageBlock]
    let toolCalls: [ToolCall]
    let searchActivities: [SearchActivity]
    let codeExecutionActivities: [CodeExecutionActivity]
    let codexToolActivities: [CodexToolActivity]
    let agentToolActivities: [CodexToolActivity]
    let assistantModelLabel: String?
    let assistantModelID: String?
    let assistantProviderIconID: String?
    let responseMetrics: ResponseMetrics?
    let highlights: [MessageHighlightSnapshot]
    let copyText: String
    let preferredRenderMode: MessageRenderMode
    let isMemoryIntensiveAssistantContent: Bool
    let collapsedPreview: LightweightMessagePreview?
    let canEditUserMessage: Bool
    let canDeleteResponse: Bool
    let perMessageMCPServerNames: [String]

    init(
        id: UUID,
        contextThreadID: UUID?,
        role: String,
        timestamp: Date,
        renderedBlocks: [RenderedMessageBlock],
        toolCalls: [ToolCall],
        searchActivities: [SearchActivity],
        codeExecutionActivities: [CodeExecutionActivity],
        codexToolActivities: [CodexToolActivity],
        agentToolActivities: [CodexToolActivity],
        assistantModelLabel: String?,
        assistantModelID: String? = nil,
        assistantProviderIconID: String?,
        responseMetrics: ResponseMetrics?,
        highlights: [MessageHighlightSnapshot] = [],
        copyText: String,
        preferredRenderMode: MessageRenderMode,
        isMemoryIntensiveAssistantContent: Bool,
        collapsedPreview: LightweightMessagePreview?,
        canEditUserMessage: Bool,
        canDeleteResponse: Bool,
        perMessageMCPServerNames: [String]
    ) {
        self.id = id
        self.contextThreadID = contextThreadID
        self.role = role
        self.timestamp = timestamp
        self.renderedBlocks = renderedBlocks
        self.toolCalls = toolCalls
        self.searchActivities = searchActivities
        self.codeExecutionActivities = codeExecutionActivities
        self.codexToolActivities = codexToolActivities
        self.agentToolActivities = agentToolActivities
        self.assistantModelLabel = assistantModelLabel
        self.assistantModelID = assistantModelID
        self.assistantProviderIconID = assistantProviderIconID
        self.responseMetrics = responseMetrics
        self.highlights = highlights
        self.copyText = copyText
        self.preferredRenderMode = preferredRenderMode
        self.isMemoryIntensiveAssistantContent = isMemoryIntensiveAssistantContent
        self.collapsedPreview = collapsedPreview
        self.canEditUserMessage = canEditUserMessage
        self.canDeleteResponse = canDeleteResponse
        self.perMessageMCPServerNames = perMessageMCPServerNames
    }

    var isUser: Bool { role == MessageRole.user.rawValue }
    var isAssistant: Bool { role == MessageRole.assistant.rawValue }
    var isTool: Bool { role == MessageRole.tool.rawValue }

    var visibleToolCalls: [ToolCall] {
        toolCalls.filter { call in
            !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
                && !isGoogleProviderNativeToolName(call.name)
                && !AgentToolHub.isAgentFunctionName(call.name)
        }
    }

    func collapsedPreviewForDisplay(in renderMode: MessageRenderMode) -> LightweightMessagePreview? {
        guard isAssistant, renderMode == .collapsedPreview else { return nil }
        return collapsedPreview
    }
}
