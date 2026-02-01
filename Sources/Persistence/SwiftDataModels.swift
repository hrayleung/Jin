import Foundation
import SwiftData

/// Conversation entity (SwiftData)
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    var providerID: String
    var modelID: String
    var modelConfigData: Data // Codable GenerationControls

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity] = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        modelConfigData: Data
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
    }

    /// Convert to domain model
    func toDomain() throws -> Conversation {
        let decoder = JSONDecoder()
        let controls = try decoder.decode(GenerationControls.self, from: modelConfigData)

        let modelConfig = ModelConfig(
            providerID: providerID,
            modelID: modelID,
            controls: controls
        )

        return Conversation(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            messages: try messages.sorted(by: { $0.timestamp < $1.timestamp }).map { try $0.toDomain() },
            modelConfig: modelConfig,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from domain model
    static func fromDomain(_ conversation: Conversation) throws -> ConversationEntity {
        let encoder = JSONEncoder()
        let modelConfigData = try encoder.encode(conversation.modelConfig.controls)

        return ConversationEntity(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            systemPrompt: conversation.systemPrompt,
            providerID: conversation.modelConfig.providerID,
            modelID: conversation.modelConfig.modelID,
            modelConfigData: modelConfigData
        )
    }
}

/// Message entity (SwiftData)
@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String // MessageRole.rawValue
    var timestamp: Date
    var contentData: Data // Codable [ContentPart]
    var toolCallsData: Data?
    var toolResultsData: Data?
    var thinkingVisible: Bool

    @Relationship var conversation: ConversationEntity?

    init(
        id: UUID = UUID(),
        role: String,
        timestamp: Date = Date(),
        contentData: Data,
        toolCallsData: Data? = nil,
        toolResultsData: Data? = nil,
        thinkingVisible: Bool = true
    ) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.contentData = contentData
        self.toolCallsData = toolCallsData
        self.toolResultsData = toolResultsData
        self.thinkingVisible = thinkingVisible
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

        return Message(
            id: id,
            role: messageRole,
            content: content,
            toolCalls: toolCalls,
            toolResults: toolResults,
            timestamp: timestamp
        )
    }

    /// Create from domain model
    static func fromDomain(_ message: Message) throws -> MessageEntity {
        let encoder = JSONEncoder()
        let contentData = try encoder.encode(message.content)
        let toolCallsData = try message.toolCalls.map { try encoder.encode($0) }
        let toolResultsData = try message.toolResults.map { try encoder.encode($0) }

        return MessageEntity(
            id: message.id,
            role: message.role.rawValue,
            timestamp: message.timestamp,
            contentData: contentData,
            toolCallsData: toolCallsData,
            toolResultsData: toolResultsData
        )
    }
}

/// Provider config entity (SwiftData)
@Model
final class ProviderConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var typeRaw: String // ProviderType.rawValue
    var apiKey: String?
    var serviceAccountJSON: String?
    var apiKeyKeychainID: String?
    var baseURL: String?
    var modelsData: Data // Codable [ModelInfo]

    init(
        id: String,
        name: String,
        typeRaw: String,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        apiKeyKeychainID: String? = nil,
        baseURL: String? = nil,
        modelsData: Data
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.apiKeyKeychainID = apiKeyKeychainID
        self.baseURL = baseURL
        self.modelsData = modelsData
    }

    /// Convert to domain model
    func toDomain() throws -> ProviderConfig {
        guard let providerType = ProviderType(rawValue: typeRaw) else {
            throw PersistenceError.invalidProviderType(typeRaw)
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([ModelInfo].self, from: modelsData)

        return ProviderConfig(
            id: id,
            name: name,
            type: providerType,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON,
            apiKeyKeychainID: apiKeyKeychainID,
            baseURL: baseURL,
            models: models
        )
    }

    /// Create from domain model
    static func fromDomain(_ config: ProviderConfig) throws -> ProviderConfigEntity {
        let encoder = JSONEncoder()
        let modelsData = try encoder.encode(config.models)

        return ProviderConfigEntity(
            id: config.id,
            name: config.name,
            typeRaw: config.type.rawValue,
            apiKey: config.apiKey,
            serviceAccountJSON: config.serviceAccountJSON,
            apiKeyKeychainID: config.apiKeyKeychainID,
            baseURL: config.baseURL,
            modelsData: modelsData
        )
    }
}

/// MCP server config entity (SwiftData)
@Model
final class MCPServerConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var command: String
    var argsData: Data
    var envData: Data?
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    var isLongRunning: Bool

    init(
        id: String,
        name: String,
        command: String,
        argsData: Data,
        envData: Data? = nil,
        isEnabled: Bool = false,
        runToolsAutomatically: Bool = true,
        isLongRunning: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.argsData = argsData
        self.envData = envData
        self.isEnabled = isEnabled
        self.runToolsAutomatically = runToolsAutomatically
        self.isLongRunning = isLongRunning
    }
}

/// Attachment entity (SwiftData)
@Model
final class AttachmentEntity {
    @Attribute(.unique) var id: UUID
    var filename: String
    var mimeType: String
    var fileURL: URL
    var uploadedAt: Date

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        fileURL: URL,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.fileURL = fileURL
        self.uploadedAt = uploadedAt
    }
}

/// Persistence errors
enum PersistenceError: Error, LocalizedError {
    case invalidRole(String)
    case invalidProviderType(String)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidRole(let role):
            return "Invalid message role: \(role)"
        case .invalidProviderType(let type):
            return "Invalid provider type: \(type)"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}
