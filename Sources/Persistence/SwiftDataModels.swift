import Foundation
import SwiftData

/// Assistant entity (SwiftData)
@Model
final class AssistantEntity {
    @Attribute(.unique) var id: String
    var name: String
    var icon: String?
    var assistantDescription: String?
    var systemInstruction: String
    var temperature: Double
    var maxOutputTokens: Int?
    /// `nil` means "default".
    var truncateMessages: Bool?
    /// Maximum number of messages to keep in history (nil = unlimited)
    var maxHistoryMessages: Int?
    /// `nil` means "default".
    var replyLanguage: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \ConversationEntity.assistant)
    var conversations: [ConversationEntity] = []

    init(
        id: String,
        name: String,
        icon: String? = nil,
        assistantDescription: String? = nil,
        systemInstruction: String = "",
        temperature: Double = 0.1,
        maxOutputTokens: Int? = nil,
        truncateMessages: Bool? = nil,
        maxHistoryMessages: Int? = nil,
        replyLanguage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.assistantDescription = assistantDescription
        self.systemInstruction = systemInstruction
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.truncateMessages = truncateMessages
        self.maxHistoryMessages = maxHistoryMessages
        self.replyLanguage = replyLanguage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}

/// Conversation entity (SwiftData)
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var isStarred: Bool?
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    var providerID: String
    var modelID: String
    var modelConfigData: Data // Codable GenerationControls

    @Relationship var assistant: AssistantEntity?
    @Relationship var project: ProjectEntity?

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity] = []

    init(
        id: UUID = UUID(),
        title: String,
        isStarred: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        assistant: AssistantEntity? = nil,
        project: ProjectEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.assistant = assistant
        self.project = project
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
    // Snapshot of the model used to generate this message (primarily for assistant replies).
    var generatedProviderID: String?
    var generatedModelID: String?
    var generatedModelName: String?

    @Relationship var conversation: ConversationEntity?

    init(
        id: UUID = UUID(),
        role: String,
        timestamp: Date = Date(),
        contentData: Data,
        toolCallsData: Data? = nil,
        toolResultsData: Data? = nil,
        generatedProviderID: String? = nil,
        generatedModelID: String? = nil,
        generatedModelName: String? = nil,
        thinkingVisible: Bool = true
    ) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.contentData = contentData
        self.toolCallsData = toolCallsData
        self.toolResultsData = toolResultsData
        self.generatedProviderID = generatedProviderID
        self.generatedModelID = generatedModelID
        self.generatedModelName = generatedModelName
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
    var iconID: String?
    var apiKey: String?
    var serviceAccountJSON: String?
    // Legacy: no longer used (credentials are stored directly on this entity).
    var apiKeyKeychainID: String?
    var baseURL: String?
    var modelsData: Data // Codable [ModelInfo]

    init(
        id: String,
        name: String,
        typeRaw: String,
        iconID: String? = nil,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        apiKeyKeychainID: String? = nil,
        baseURL: String? = nil,
        modelsData: Data
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.iconID = iconID
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
            iconID: iconID,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON,
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
            iconID: config.iconID,
            apiKey: config.apiKey,
            serviceAccountJSON: config.serviceAccountJSON,
            apiKeyKeychainID: nil,
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
    // Legacy stdio fields kept for schema stability.
    var command: String
    var argsData: Data
    var envData: Data?
    var transportKindRaw: String = MCPTransportKind.stdio.rawValue
    var transportData: Data = Data()
    var lifecycleRaw: String = MCPLifecyclePolicy.persistent.rawValue
    var disabledToolsData: Data?
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    // Legacy mirror of lifecycle for old code paths.
    var isLongRunning: Bool

    init(
        id: String,
        name: String,
        command: String = "",
        argsData: Data = Data(),
        envData: Data? = nil,
        transportKindRaw: String,
        transportData: Data,
        lifecycleRaw: String = MCPLifecyclePolicy.persistent.rawValue,
        disabledToolsData: Data? = nil,
        isEnabled: Bool = false,
        runToolsAutomatically: Bool = true,
        isLongRunning: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.argsData = argsData
        self.envData = envData
        self.transportKindRaw = transportKindRaw
        self.transportData = transportData
        self.lifecycleRaw = lifecycleRaw
        self.disabledToolsData = disabledToolsData
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

/// Project entity (SwiftData)
@Model
final class ProjectEntity {
    @Attribute(.unique) var id: String
    var name: String
    var icon: String?
    var projectDescription: String?
    var customInstruction: String?
    var contextMode: String // "directInjection" (default), "rag"
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var embeddingProviderID: String?
    var embeddingModelID: String?
    var rerankProviderID: String?
    var rerankModelID: String?

    @Relationship(deleteRule: .cascade, inverse: \ProjectDocumentEntity.project)
    var documents: [ProjectDocumentEntity] = []

    @Relationship(deleteRule: .nullify, inverse: \ConversationEntity.project)
    var conversations: [ConversationEntity] = []

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String? = nil,
        projectDescription: String? = nil,
        customInstruction: String? = nil,
        contextMode: String = ProjectContextMode.directInjection.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0,
        embeddingProviderID: String? = nil,
        embeddingModelID: String? = nil,
        rerankProviderID: String? = nil,
        rerankModelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.projectDescription = projectDescription
        self.customInstruction = customInstruction
        self.contextMode = contextMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.embeddingProviderID = embeddingProviderID
        self.embeddingModelID = embeddingModelID
        self.rerankProviderID = rerankProviderID
        self.rerankModelID = rerankModelID
    }
}

/// Project document entity (SwiftData)
@Model
final class ProjectDocumentEntity {
    @Attribute(.unique) var id: UUID
    var filename: String
    var mimeType: String
    var fileURL: URL
    var extractedText: String?
    var fileSizeBytes: Int64
    var addedAt: Date
    var processingStatus: String // "pending", "extracting", "indexing", "ready", "failed"
    var processingError: String?
    var chunkCount: Int

    @Relationship var project: ProjectEntity?

    @Relationship(deleteRule: .cascade, inverse: \DocumentChunkEntity.document)
    var chunks: [DocumentChunkEntity] = []

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        fileURL: URL,
        extractedText: String? = nil,
        fileSizeBytes: Int64 = 0,
        addedAt: Date = Date(),
        processingStatus: String = "pending",
        processingError: String? = nil,
        chunkCount: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.fileURL = fileURL
        self.extractedText = extractedText
        self.fileSizeBytes = fileSizeBytes
        self.addedAt = addedAt
        self.processingStatus = processingStatus
        self.processingError = processingError
        self.chunkCount = chunkCount
    }
}

/// Document chunk entity for RAG (SwiftData)
@Model
final class DocumentChunkEntity {
    @Attribute(.unique) var id: UUID
    var chunkIndex: Int
    var text: String
    var embeddingData: Data?
    var startOffset: Int
    var endOffset: Int

    @Relationship var document: ProjectDocumentEntity?

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        text: String,
        embeddingData: Data? = nil,
        startOffset: Int,
        endOffset: Int
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.text = text
        self.embeddingData = embeddingData
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

/// Embedding provider config entity (SwiftData)
@Model
final class EmbeddingProviderConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var typeRaw: String // "openai", "cohere", "voyage", "jina", "gemini", "openaiCompatible"
    var apiKey: String?
    var baseURL: String?
    var defaultModelID: String?
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        typeRaw: String,
        apiKey: String? = nil,
        baseURL: String? = nil,
        defaultModelID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModelID = defaultModelID
        self.isEnabled = isEnabled
    }
}

/// Rerank provider config entity (SwiftData)
@Model
final class RerankProviderConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var typeRaw: String // "cohere", "voyage", "jina"
    var apiKey: String?
    var baseURL: String?
    var defaultModelID: String?
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        typeRaw: String,
        apiKey: String? = nil,
        baseURL: String? = nil,
        defaultModelID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModelID = defaultModelID
        self.isEnabled = isEnabled
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
