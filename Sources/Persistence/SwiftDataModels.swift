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
    var artifactsEnabled: Bool?
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    /// Legacy compatibility snapshot of the currently active thread's provider.
    var providerID: String
    /// Legacy compatibility snapshot of the currently active thread's model.
    var modelID: String
    /// Legacy compatibility snapshot of the currently active thread's controls.
    var modelConfigData: Data // Codable GenerationControls
    /// Currently active model thread for composer/send.
    var activeThreadID: UUID?

    @Relationship var assistant: AssistantEntity?

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationModelThreadEntity.conversation)
    var modelThreads: [ConversationModelThreadEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \MessageHighlightEntity.conversation)
    var messageHighlights: [MessageHighlightEntity] = []

    init(
        id: UUID = UUID(),
        title: String,
        isStarred: Bool = false,
        artifactsEnabled: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        activeThreadID: UUID? = nil,
        assistant: AssistantEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.isStarred = isStarred
        self.artifactsEnabled = artifactsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.activeThreadID = activeThreadID
        self.assistant = assistant
    }

    /// Convert to domain model
    func toDomain() throws -> Conversation {
        let decoder = JSONDecoder()
        let threadByID = Dictionary(uniqueKeysWithValues: modelThreads.map { ($0.id, $0) })
        let activeThread = activeThreadID.flatMap { threadByID[$0] } ?? modelThreads.first

        let effectiveProviderID = activeThread?.providerID ?? providerID
        let effectiveModelID = activeThread?.modelID ?? modelID
        let effectiveModelConfigData = activeThread?.modelConfigData ?? modelConfigData

        let controls = try decoder.decode(GenerationControls.self, from: effectiveModelConfigData)

        let modelConfig = ModelConfig(
            providerID: effectiveProviderID,
            modelID: effectiveModelID,
            controls: controls
        )

        return Conversation(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            artifactsEnabled: artifactsEnabled == true,
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
            artifactsEnabled: conversation.artifactsEnabled,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            systemPrompt: conversation.systemPrompt,
            providerID: conversation.modelConfig.providerID,
            modelID: conversation.modelConfig.modelID,
            modelConfigData: modelConfigData
        )
    }
}

/// Per-conversation model thread (independent context + controls).
@Model
final class ConversationModelThreadEntity {
    @Attribute(.unique) var id: UUID
    var providerID: String
    var modelID: String
    var modelConfigData: Data
    var displayOrder: Int
    var isSelected: Bool
    var isPrimary: Bool
    var lastActivatedAt: Date
    var createdAt: Date
    var updatedAt: Date

    @Relationship var conversation: ConversationEntity?

    init(
        id: UUID = UUID(),
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        displayOrder: Int = 0,
        isSelected: Bool = true,
        isPrimary: Bool = false,
        lastActivatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.displayOrder = displayOrder
        self.isSelected = isSelected
        self.isPrimary = isPrimary
        self.lastActivatedAt = lastActivatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

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
    var codexToolActivitiesData: Data?
    var agentToolActivitiesData: Data?
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
        codexToolActivitiesData: Data? = nil,
        agentToolActivitiesData: Data? = nil,
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
        self.codexToolActivitiesData = codexToolActivitiesData
        self.agentToolActivitiesData = agentToolActivitiesData
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
        let codexToolActivities = try codexToolActivitiesData.flatMap { try decoder.decode([CodexToolActivity].self, from: $0) }
        let agentToolActivities = try agentToolActivitiesData.flatMap { try decoder.decode([CodexToolActivity].self, from: $0) }
        let perMessageMCPServerNames = try perMessageMCPServerNamesData.flatMap { try decoder.decode([String].self, from: $0) }

        return Message(
            id: id,
            role: messageRole,
            content: content,
            toolCalls: toolCalls,
            toolResults: toolResults,
            searchActivities: searchActivities,
            codeExecutionActivities: codeExecutionActivities,
            codexToolActivities: codexToolActivities,
            agentToolActivities: agentToolActivities,
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
        let codexToolActivitiesData = try message.codexToolActivities.map { try encoder.encode($0) }
        let agentToolActivitiesData = try message.agentToolActivities.map { try encoder.encode($0) }
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
            codexToolActivitiesData: codexToolActivitiesData,
            agentToolActivitiesData: agentToolActivitiesData,
            perMessageMCPServerNamesData: perMessageMCPServerNamesData
        )
    }
}

@Model
final class MessageHighlightEntity {
    @Attribute(.unique) var id: UUID
    var messageID: UUID
    var conversationID: UUID
    var contextThreadID: UUID?
    var anchorID: String
    var selectedText: String
    var prefixContext: String?
    var suffixContext: String?
    var startOffset: Int
    var endOffset: Int
    var colorStyleRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship var conversation: ConversationEntity?
    @Relationship var message: MessageEntity?

    init(
        id: UUID = UUID(),
        messageID: UUID,
        conversationID: UUID,
        contextThreadID: UUID? = nil,
        anchorID: String,
        selectedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil,
        startOffset: Int,
        endOffset: Int,
        colorStyle: MessageHighlightColorStyle = .readerYellow,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.conversationID = conversationID
        self.contextThreadID = contextThreadID
        self.anchorID = anchorID
        self.selectedText = selectedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.colorStyleRaw = colorStyle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var colorStyle: MessageHighlightColorStyle {
        get { MessageHighlightColorStyle(rawValue: colorStyleRaw) ?? .readerYellow }
        set { colorStyleRaw = newValue.rawValue }
    }

    func syncIDsWithRelationships() {
        if let message {
            messageID = message.id
        }
        if let conversation {
            conversationID = conversation.id
        }
    }

    func makeSnapshot() -> MessageHighlightSnapshot {
        return MessageHighlightSnapshot(
            id: id,
            messageID: messageID,
            contextThreadID: contextThreadID,
            anchorID: anchorID,
            selectedText: selectedText,
            prefixContext: prefixContext,
            suffixContext: suffixContext,
            startOffset: startOffset,
            endOffset: endOffset,
            colorStyle: colorStyle,
            createdAt: createdAt,
            updatedAt: updatedAt
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
    // Legacy: preserved for schema compatibility with older GitHub OAuth builds.
    var oauthClientID: String?
    // Legacy: no longer used (credentials are stored directly on this entity).
    var apiKeyKeychainID: String?
    var baseURL: String?
    var modelsData: Data // Codable [ModelInfo]
    var isEnabled: Bool = true

    init(
        id: String,
        name: String,
        typeRaw: String,
        iconID: String? = nil,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        oauthClientID: String? = nil,
        apiKeyKeychainID: String? = nil,
        baseURL: String? = nil,
        modelsData: Data,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.iconID = iconID
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.oauthClientID = oauthClientID
        self.apiKeyKeychainID = apiKeyKeychainID
        self.baseURL = baseURL
        self.modelsData = modelsData
        self.isEnabled = isEnabled
    }

    /// Convert to domain model
    func toDomain() throws -> ProviderConfig {
        guard let providerType = ProviderType(rawValue: typeRaw) else {
            throw PersistenceError.invalidProviderType(typeRaw)
        }

        let decoder = JSONDecoder()
        let models: [ModelInfo]
        if providerType == .claudeManagedAgents {
            models = []
        } else {
            models = try decoder.decode([ModelInfo].self, from: modelsData)
        }

        var config = ProviderConfig(
            id: id,
            name: name,
            type: providerType,
            iconID: iconID,
            authModeHint: apiKeyKeychainID,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON,
            baseURL: baseURL,
            models: models,
            isEnabled: isEnabled
        )
        if providerType == .claudeManagedAgents {
            config.normalizeClaudeManagedAgentDefaults()
        }
        return config
    }

    /// Create from domain model
    static func fromDomain(_ config: ProviderConfig) throws -> ProviderConfigEntity {
        let encoder = JSONEncoder()
        let modelsData = try encoder.encode(config.hasLocalModelCatalog ? config.models : [])

        return ProviderConfigEntity(
            id: config.id,
            name: config.name,
            typeRaw: config.type.rawValue,
            iconID: config.iconID,
            apiKey: config.apiKey,
            serviceAccountJSON: config.serviceAccountJSON,
            oauthClientID: nil,
            apiKeyKeychainID: config.authModeHint,
            baseURL: config.baseURL,
            modelsData: modelsData,
            isEnabled: config.isEnabled
        )
    }
}

/// MCP server config entity (SwiftData)
@Model
final class MCPServerConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var iconID: String?
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
        iconID: String? = nil,
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
        self.iconID = iconID
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
