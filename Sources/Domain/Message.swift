import Foundation

/// Message in the conversation
struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: [ContentPart]
    let toolCalls: [ToolCall]?
    let toolResults: [ToolResult]?
    let searchActivities: [SearchActivity]?
    let codeExecutionActivities: [CodeExecutionActivity]?
    let timestamp: Date
    /// MCP server names selected via slash command for this specific message.
    let perMessageMCPServerNames: [String]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [ContentPart],
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        searchActivities: [SearchActivity]? = nil,
        codeExecutionActivities: [CodeExecutionActivity]? = nil,
        timestamp: Date = Date(),
        perMessageMCPServerNames: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.searchActivities = searchActivities
        self.codeExecutionActivities = codeExecutionActivities
        self.timestamp = timestamp
        self.perMessageMCPServerNames = perMessageMCPServerNames
    }
}
