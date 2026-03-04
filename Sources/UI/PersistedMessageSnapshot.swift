import Foundation

struct PersistedMessageSnapshot: Sendable {
    let id: UUID
    let role: String
    let timestamp: Date
    let contextThreadID: UUID?
    let turnID: UUID?
    let contentData: Data
    let toolCallsData: Data?
    let toolResultsData: Data?
    let searchActivitiesData: Data?

    init(_ entity: MessageEntity) {
        self.id = entity.id
        self.role = entity.role
        self.timestamp = entity.timestamp
        self.contextThreadID = entity.contextThreadID
        self.turnID = entity.turnID
        self.contentData = entity.contentData
        self.toolCallsData = entity.toolCallsData
        self.toolResultsData = entity.toolResultsData
        self.searchActivitiesData = entity.searchActivitiesData
    }

    func toDomain(using decoder: JSONDecoder) -> Message? {
        guard let messageRole = MessageRole(rawValue: role) else { return nil }
        guard let content = try? decoder.decode([ContentPart].self, from: contentData) else { return nil }

        let toolCalls = toolCallsData.flatMap { try? decoder.decode([ToolCall].self, from: $0) }
        let toolResults = toolResultsData.flatMap { try? decoder.decode([ToolResult].self, from: $0) }
        let searchActivities = searchActivitiesData.flatMap { try? decoder.decode([SearchActivity].self, from: $0) }

        return Message(
            id: id,
            role: messageRole,
            content: content,
            toolCalls: toolCalls,
            toolResults: toolResults,
            searchActivities: searchActivities,
            timestamp: timestamp
        )
    }
}
