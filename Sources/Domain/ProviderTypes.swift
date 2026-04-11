import Foundation

enum ModelType: String, Codable, CaseIterable {
    case chat
    case image
    case video

    var displayName: String {
        switch self {
        case .chat: return "Chat"
        case .image: return "Image"
        case .video: return "Video"
        }
    }
}

struct ModelOverrides: Codable, Equatable {
    var modelType: ModelType?
    var contextWindow: Int?
    var maxOutputTokens: Int?
    var capabilities: ModelCapability?
    var reasoningConfig: ModelReasoningConfig?
    var reasoningCanDisable: Bool?
    var webSearchSupported: Bool?

    init(
        modelType: ModelType? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        capabilities: ModelCapability? = nil,
        reasoningConfig: ModelReasoningConfig? = nil,
        reasoningCanDisable: Bool? = nil,
        webSearchSupported: Bool? = nil
    ) {
        self.modelType = modelType
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.capabilities = capabilities
        self.reasoningConfig = reasoningConfig
        self.reasoningCanDisable = reasoningCanDisable
        self.webSearchSupported = webSearchSupported
    }

    var isEmpty: Bool {
        modelType == nil
            && contextWindow == nil
            && maxOutputTokens == nil
            && capabilities == nil
            && reasoningConfig == nil
            && reasoningCanDisable == nil
            && webSearchSupported == nil
    }
}

/// Provider type.
enum ProviderType: String, Codable, CaseIterable {
    case anthropic
    case claudeManagedAgents
    case cerebras
    case cloudflareAIGateway
    case codexAppServer
    case cohere
    case deepinfra
    case deepseek
    case fireworks
    case gemini
    case githubCopilot
    case groq
    case minimax
    case minimaxCodingPlan
    case mistral
    case morphllm
    case openai
    case openaiCompatible
    case openaiWebSocket
    case opencodeGo
    case openrouter
    case perplexity
    case sambanova
    case together
    case vercelAIGateway
    case vertexai
    case xai
    case zhipuCodingPlan

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .openaiWebSocket: return "OpenAI (WebSocket)"
        case .opencodeGo: return "OpenCode Go"
        case .codexAppServer: return "Codex App Server (Beta)"
        case .githubCopilot: return "GitHub Copilot"
        case .openaiCompatible: return "OpenAI Compatible"
        case .cloudflareAIGateway: return "Cloudflare AI Gateway"
        case .vercelAIGateway: return "Vercel AI Gateway"
        case .openrouter: return "OpenRouter"
        case .anthropic: return "Anthropic"
        case .claudeManagedAgents: return "Claude Managed Agents"
        case .perplexity: return "Perplexity"
        case .groq: return "Groq"
        case .cohere: return "Cohere"
        case .mistral: return "Mistral"
        case .deepinfra: return "DeepInfra"
        case .together: return "Together AI"
        case .xai: return "xAI"
        case .deepseek: return "DeepSeek"
        case .zhipuCodingPlan: return "Zhipu Coding Plan"
        case .minimax: return "MiniMax"
        case .minimaxCodingPlan: return "MiniMax Coding Plan"
        case .fireworks: return "Fireworks"
        case .cerebras: return "Cerebras"
        case .sambanova: return "SambaNova"
        case .morphllm: return "MorphLLM"
        case .gemini: return "Gemini (AI Studio)"
        case .vertexai: return "Vertex AI"
        }
    }

    /// Providers using the Google generative AI API surface (Gemini API / Vertex AI).
    var isGoogleFamily: Bool {
        switch self {
        case .gemini, .vertexai: return true
        default: return false
        }
    }

    /// Providers that support native prompt caching features.
    var supportsNativePromptCaching: Bool {
        switch self {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai, .gemini, .vertexai:
            return true
        default:
            return false
        }
    }

    /// Providers that support native PDF file uploads (as opposed to OCR extraction).
    var supportsNativePDFUpload: Bool {
        switch self {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .perplexity, .xai, .gemini, .vertexai:
            return true
        default:
            return false
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .openaiWebSocket: return "wss://api.openai.com/v1"
        case .opencodeGo: return nil
        case .codexAppServer: return "ws://127.0.0.1:4500"
        case .githubCopilot: return "https://models.github.ai/inference"
        case .openaiCompatible: return "https://api.openai.com/v1"
        case .cloudflareAIGateway: return "https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_slug}/compat"
        case .vercelAIGateway: return "https://ai-gateway.vercel.sh/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .claudeManagedAgents: return "https://api.anthropic.com"
        case .perplexity: return "https://api.perplexity.ai"
        case .groq: return "https://api.groq.com/openai/v1"
        case .cohere: return "https://api.cohere.com/v2"
        case .mistral: return "https://api.mistral.ai/v1"
        case .deepinfra: return "https://api.deepinfra.com/v1/openai"
        case .together: return "https://api.together.xyz/v1"
        case .xai: return "https://api.x.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .zhipuCodingPlan: return "https://open.bigmodel.cn/api/coding/paas/v4"
        case .minimax: return "https://api.minimax.io/v1"
        case .minimaxCodingPlan: return "https://api.minimaxi.com/anthropic/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .sambanova: return "https://api.sambanova.ai/v1"
        case .morphllm: return "https://api.morphllm.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .vertexai: return nil
        }
    }
}

/// Provider configuration.
struct ProviderConfig: Identifiable, Codable {
    let id: String
    let name: String
    let type: ProviderType
    var iconID: String?
    /// Optional provider-specific auth mode hint persisted with this provider config.
    var authModeHint: String?
    var apiKey: String?
    var serviceAccountJSON: String?
    var baseURL: String?
    var models: [ModelInfo]
    var isEnabled: Bool

    init(
        id: String,
        name: String,
        type: ProviderType,
        iconID: String? = nil,
        authModeHint: String? = nil,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        baseURL: String? = nil,
        models: [ModelInfo] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.iconID = iconID
        self.authModeHint = authModeHint
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.baseURL = baseURL
        self.models = models
        self.isEnabled = isEnabled
    }

    var hasLocalModelCatalog: Bool {
        type != .claudeManagedAgents
    }
}

/// Model information.
struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let capabilities: ModelCapability
    let contextWindow: Int
    let maxOutputTokens: Int?
    let reasoningConfig: ModelReasoningConfig?
    var overrides: ModelOverrides?
    var catalogMetadata: ModelCatalogMetadata?
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, capabilities, contextWindow, maxOutputTokens, reasoningConfig, overrides, catalogMetadata, isEnabled
    }

    init(
        id: String,
        name: String,
        capabilities: ModelCapability = [],
        contextWindow: Int,
        maxOutputTokens: Int? = nil,
        reasoningConfig: ModelReasoningConfig? = nil,
        overrides: ModelOverrides? = nil,
        catalogMetadata: ModelCatalogMetadata? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningConfig = reasoningConfig
        self.overrides = overrides
        self.catalogMetadata = catalogMetadata
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        capabilities = try container.decode(ModelCapability.self, forKey: .capabilities)
        contextWindow = try container.decode(Int.self, forKey: .contextWindow)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        reasoningConfig = try container.decodeIfPresent(ModelReasoningConfig.self, forKey: .reasoningConfig)
        overrides = try container.decodeIfPresent(ModelOverrides.self, forKey: .overrides)
        catalogMetadata = try container.decodeIfPresent(ModelCatalogMetadata.self, forKey: .catalogMetadata)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(contextWindow, forKey: .contextWindow)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encode(reasoningConfig, forKey: .reasoningConfig)
        try container.encodeIfPresent(overrides, forKey: .overrides)
        try container.encodeIfPresent(catalogMetadata, forKey: .catalogMetadata)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

/// Model capabilities (option set).
struct ModelCapability: OptionSet, Codable, Equatable {
    let rawValue: Int

    static let streaming = ModelCapability(rawValue: 1 << 0)
    static let toolCalling = ModelCapability(rawValue: 1 << 1)
    static let vision = ModelCapability(rawValue: 1 << 2)
    static let audio = ModelCapability(rawValue: 1 << 3)
    static let reasoning = ModelCapability(rawValue: 1 << 4)
    static let promptCaching = ModelCapability(rawValue: 1 << 5)
    static let nativePDF = ModelCapability(rawValue: 1 << 6)
    static let imageGeneration = ModelCapability(rawValue: 1 << 7)
    static let videoGeneration = ModelCapability(rawValue: 1 << 8)
    static let codeExecution = ModelCapability(rawValue: 1 << 9)

    static let all: ModelCapability = [
        .streaming, .toolCalling, .vision, .audio, .reasoning,
        .promptCaching, .nativePDF, .imageGeneration, .videoGeneration, .codeExecution
    ]
}

/// Model configuration.
struct ModelConfig: Codable {
    let providerID: String
    let modelID: String
    var controls: GenerationControls
    var enabledTools: [String]

    init(
        providerID: String,
        modelID: String,
        controls: GenerationControls = GenerationControls(),
        enabledTools: [String] = []
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.controls = controls
        self.enabledTools = enabledTools
    }
}

/// Conversation model.
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var systemPrompt: String?
    var artifactsEnabled: Bool
    var messages: [Message]
    var modelConfig: ModelConfig
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        systemPrompt: String? = nil,
        artifactsEnabled: Bool = false,
        messages: [Message] = [],
        modelConfig: ModelConfig,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.artifactsEnabled = artifactsEnabled
        self.messages = messages
        self.modelConfig = modelConfig
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Token usage statistics.
struct Usage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let cachedTokens: Int?
    let cacheCreationTokens: Int?
    let cacheWriteTokens: Int?
    let serviceTier: String?
    let inferenceGeo: String?

    var totalTokens: Int {
        inputTokens + outputTokens + (thinkingTokens ?? 0)
    }

    init(
        inputTokens: Int,
        outputTokens: Int,
        thinkingTokens: Int? = nil,
        cachedTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        serviceTier: String? = nil,
        inferenceGeo: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thinkingTokens = thinkingTokens
        self.cachedTokens = cachedTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.serviceTier = serviceTier
        self.inferenceGeo = inferenceGeo
    }
}
