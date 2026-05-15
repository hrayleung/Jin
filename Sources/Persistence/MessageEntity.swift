import Foundation
import SwiftData

/// Message entity (SwiftData)
@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String // MessageRole.rawValue
    var timestamp: Date
    /// Conversation model thread this message belongs to.
    var contextThreadID: UUID?
    /// Optional cross-thread turn fan-out identifier.
    var turnID: UUID?
    var contentData: Data // Codable [ContentPart]
    var toolCallsData: Data?
    var toolResultsData: Data?
    var searchActivitiesData: Data?
    var codeExecutionActivitiesData: Data?
    var responseMetricsData: Data?
    var thinkingVisible: Bool
    // Snapshot of the model used to generate this message (primarily for assistant replies).
    var generatedProviderID: String?
    var generatedModelID: String?
    var generatedModelName: String?
    /// Per-message MCP server names selected via slash command. Stored as JSON-encoded [String].
    var perMessageMCPServerNamesData: Data?
    /// Per-message MCP server IDs for restoring selection on edit. Stored as JSON-encoded [String].
    var perMessageMCPServerIDsData: Data?

    @Relationship var conversation: ConversationEntity?

    @Relationship(deleteRule: .cascade, inverse: \MessageHighlightEntity.message)
    var highlights: [MessageHighlightEntity] = []

    init(
        id: UUID = UUID(),
        role: String,
        timestamp: Date = Date(),
        contextThreadID: UUID? = nil,
        turnID: UUID? = nil,
        contentData: Data,
        toolCallsData: Data? = nil,
        toolResultsData: Data? = nil,
        searchActivitiesData: Data? = nil,
        codeExecutionActivitiesData: Data? = nil,
        responseMetricsData: Data? = nil,
        generatedProviderID: String? = nil,
        generatedModelID: String? = nil,
        generatedModelName: String? = nil,
        thinkingVisible: Bool = true,
        perMessageMCPServerNamesData: Data? = nil,
        perMessageMCPServerIDsData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.contextThreadID = contextThreadID
        self.turnID = turnID
        self.contentData = contentData
        self.toolCallsData = toolCallsData
        self.toolResultsData = toolResultsData
        self.searchActivitiesData = searchActivitiesData
        self.codeExecutionActivitiesData = codeExecutionActivitiesData
        self.responseMetricsData = responseMetricsData
        self.generatedProviderID = generatedProviderID
        self.generatedModelID = generatedModelID
        self.generatedModelName = generatedModelName
        self.thinkingVisible = thinkingVisible
        self.perMessageMCPServerNamesData = perMessageMCPServerNamesData
        self.perMessageMCPServerIDsData = perMessageMCPServerIDsData
    }

    var highlightSnapshots: [MessageHighlightSnapshot] {
        highlights
            .map { $0.makeSnapshot() }
            .sorted { lhs, rhs in
                if lhs.anchorID != rhs.anchorID {
                    return lhs.anchorID < rhs.anchorID
                }
                if lhs.startOffset != rhs.startOffset {
                    return lhs.startOffset < rhs.startOffset
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var responseMetrics: ResponseMetrics? {
        get {
            guard let responseMetricsData else { return nil }
            return try? JSONDecoder().decode(ResponseMetrics.self, from: responseMetricsData)
        }
        set {
            if let newValue {
                responseMetricsData = try? JSONEncoder().encode(newValue)
            } else {
                responseMetricsData = nil
            }
        }
    }

    /// Convert to domain model
    func toDomain() throws -> Message {
        let decoder = JSONDecoder()

        guard let messageRole = MessageRole(rawValue: role) else {
            throw PersistenceError.invalidRole(role)
        }

        let content = try decoder.decode([ContentPart].self, from: contentData)
        let toolCalls = try toolCallsData.flatMap { try decoder.decode([ToolCall].self, from: $0) }
        let toolResults = try toolResultsData.flatMap { try decoder.decode([ToolResult].self, from: $0) }
        let searchActivities = try searchActivitiesData.flatMap { try decoder.decode([SearchActivity].self, from: $0) }
        let codeExecutionActivities = try codeExecutionActivitiesData.flatMap { try decoder.decode([CodeExecutionActivity].self, from: $0) }
        let perMessageMCPServerNames = try perMessageMCPServerNamesData.flatMap { try decoder.decode([String].self, from: $0) }

        return Message(
            id: id,
            role: messageRole,
            content: content,
            toolCalls: toolCalls,
            toolResults: toolResults,
            searchActivities: searchActivities,
            codeExecutionActivities: codeExecutionActivities,
            timestamp: timestamp,
            perMessageMCPServerNames: perMessageMCPServerNames
        )
    }

    /// Create from domain model
    static func fromDomain(_ message: Message) throws -> MessageEntity {
        let encoder = JSONEncoder()
        let contentData = try encoder.encode(message.content)
        let toolCallsData = try message.toolCalls.map { try encoder.encode($0) }
        let toolResultsData = try message.toolResults.map { try encoder.encode($0) }
        let searchActivitiesData = try message.searchActivities.map { try encoder.encode($0) }
        let codeExecutionActivitiesData = try message.codeExecutionActivities.map { try encoder.encode($0) }
        let perMessageMCPServerNamesData = try message.perMessageMCPServerNames.map { try encoder.encode($0) }

        return MessageEntity(
            id: message.id,
            role: message.role.rawValue,
            timestamp: message.timestamp,
            contentData: contentData,
            toolCallsData: toolCallsData,
            toolResultsData: toolResultsData,
            searchActivitiesData: searchActivitiesData,
            codeExecutionActivitiesData: codeExecutionActivitiesData,
            perMessageMCPServerNamesData: perMessageMCPServerNamesData
        )
    }
}
