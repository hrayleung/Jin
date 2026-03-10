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
    let codexToolActivitiesData: Data?
    let perMessageMCPServerNamesData: Data?
    let responseMetricsData: Data?
    let generatedProviderID: String?
    let generatedModelID: String?
    let generatedModelName: String?

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
        self.codexToolActivitiesData = entity.codexToolActivitiesData
        self.perMessageMCPServerNamesData = entity.perMessageMCPServerNamesData
        self.responseMetricsData = entity.responseMetricsData
        self.generatedProviderID = entity.generatedProviderID
        self.generatedModelID = entity.generatedModelID
        self.generatedModelName = entity.generatedModelName
    }

    func toDomain(using decoder: JSONDecoder) -> Message? {
        guard let messageRole = MessageRole(rawValue: role) else { return nil }
        guard let content = try? decoder.decode([ContentPart].self, from: contentData) else { return nil }

        let toolCalls = toolCallsData.flatMap { try? decoder.decode([ToolCall].self, from: $0) }
        let toolResults = toolResultsData.flatMap { try? decoder.decode([ToolResult].self, from: $0) }
        let searchActivities = searchActivitiesData.flatMap { try? decoder.decode([SearchActivity].self, from: $0) }
        let codexToolActivities = codexToolActivitiesData.flatMap { try? decoder.decode([CodexToolActivity].self, from: $0) }
        let perMessageMCPServerNames = perMessageMCPServerNamesData.flatMap { try? decoder.decode([String].self, from: $0) }

        return Message(
            id: id,
            role: messageRole,
            content: content,
            toolCalls: toolCalls,
            toolResults: toolResults,
            searchActivities: searchActivities,
            codexToolActivities: codexToolActivities,
            timestamp: timestamp,
            perMessageMCPServerNames: perMessageMCPServerNames
        )
    }

    func responseMetrics(using decoder: JSONDecoder) -> ResponseMetrics? {
        responseMetricsData.flatMap { try? decoder.decode(ResponseMetrics.self, from: $0) }
    }
}
