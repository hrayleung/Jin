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
    let assistantProviderIconID: String?
    let responseMetrics: ResponseMetrics?
    let copyText: String
    let preferredRenderMode: MessageRenderMode
    let isMemoryIntensiveAssistantContent: Bool
    let collapsedPreview: LightweightMessagePreview?
    let canEditUserMessage: Bool
    let canDeleteResponse: Bool
    let perMessageMCPServerNames: [String]

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
