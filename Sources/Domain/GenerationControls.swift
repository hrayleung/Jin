import Foundation

/// Generation controls for LLM requests
struct GenerationControls: Codable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var reasoning: ReasoningControls?
    var webSearch: WebSearchControls?
    var mcpTools: MCPToolsControls?
    var providerSpecific: [String: AnyCodable] = [:] // Escape hatch for provider-specific params

    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        reasoning: ReasoningControls? = nil,
        webSearch: WebSearchControls? = nil,
        mcpTools: MCPToolsControls? = nil,
        providerSpecific: [String: AnyCodable] = [:]
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.reasoning = reasoning
        self.webSearch = webSearch
        self.mcpTools = mcpTools
        self.providerSpecific = providerSpecific
    }
}

/// MCP tool calling controls (app-provided tools via MCP servers)
struct MCPToolsControls: Codable {
    var enabled: Bool
    /// Optional allowlist of MCP server IDs for this conversation. `nil` means “all enabled servers”.
    var enabledServerIDs: [String]?

    init(enabled: Bool = true, enabledServerIDs: [String]? = nil) {
        self.enabled = enabled
        self.enabledServerIDs = enabledServerIDs
    }
}

/// Built-in web search controls (provider-native)
struct WebSearchControls: Codable {
    var enabled: Bool
    var contextSize: WebSearchContextSize?
    var sources: [WebSearchSource]?

    init(enabled: Bool = false, contextSize: WebSearchContextSize? = nil, sources: [WebSearchSource]? = nil) {
        self.enabled = enabled
        self.contextSize = contextSize
        self.sources = sources
    }
}

enum WebSearchContextSize: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        rawValue.capitalized
    }
}

enum WebSearchSource: String, Codable, CaseIterable {
    case web
    case x

    var displayName: String {
        switch self {
        case .web: return "Web"
        case .x: return "X"
        }
    }
}

/// Reasoning controls (unified for OpenAI effort and Anthropic budget)
struct ReasoningControls: Codable {
    var enabled: Bool
    var effort: ReasoningEffort? // For OpenAI, Vertex thinking_level
    var budgetTokens: Int? // For Anthropic, Vertex thinking_budget
    var summary: ReasoningSummary? // For OpenAI summary control

    init(enabled: Bool = true, effort: ReasoningEffort? = nil, budgetTokens: Int? = nil, summary: ReasoningSummary? = nil) {
        self.enabled = enabled
        self.effort = effort
        self.budgetTokens = budgetTokens
        self.summary = summary
    }
}

/// Reasoning summary detail levels (OpenAI)
enum ReasoningSummary: String, Codable, CaseIterable {
    case auto
    case concise
    case detailed

    var displayName: String {
        rawValue.capitalized
    }
}

/// Reasoning effort levels (OpenAI, Vertex Gemini 3)
enum ReasoningEffort: String, Codable, CaseIterable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh // Extra high (OpenAI GPT-5.2 only)

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extreme"
        }
    }
}

/// Model configuration
struct ModelConfig: Codable {
    let providerID: String
    let modelID: String
    var controls: GenerationControls
    var enabledTools: [String] // Tool IDs from MCP

    init(providerID: String, modelID: String, controls: GenerationControls = GenerationControls(), enabledTools: [String] = []) {
        self.providerID = providerID
        self.modelID = modelID
        self.controls = controls
        self.enabledTools = enabledTools
    }
}

/// Provider configuration
struct ProviderConfig: Identifiable, Codable {
    let id: String
    let name: String
    let type: ProviderType
    var apiKey: String?
    var serviceAccountJSON: String?
    var apiKeyKeychainID: String?
    var baseURL: String?
    var models: [ModelInfo]

    init(
        id: String,
        name: String,
        type: ProviderType,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        apiKeyKeychainID: String? = nil,
        baseURL: String? = nil,
        models: [ModelInfo] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.apiKeyKeychainID = apiKeyKeychainID
        self.baseURL = baseURL
        self.models = models
    }
}

/// Provider type
enum ProviderType: String, Codable, CaseIterable {
    case openai
    case anthropic
    case xai
    case fireworks
    case cerebras
    case vertexai

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .xai: return "xAI"
        case .fireworks: return "Fireworks"
        case .cerebras: return "Cerebras"
        case .vertexai: return "Vertex AI"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .xai:
            return "https://api.x.ai/v1"
        case .fireworks:
            return "https://api.fireworks.ai/inference/v1"
        case .cerebras:
            return "https://api.cerebras.ai/v1"
        case .vertexai:
            return nil
        }
    }
}

/// Model information
struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let capabilities: ModelCapability
    let contextWindow: Int
    let reasoningConfig: ModelReasoningConfig?

    init(
        id: String,
        name: String,
        capabilities: ModelCapability = [],
        contextWindow: Int,
        reasoningConfig: ModelReasoningConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.reasoningConfig = reasoningConfig
    }
}

/// Model capabilities (option set)
struct ModelCapability: OptionSet, Codable {
    let rawValue: Int

    static let streaming = ModelCapability(rawValue: 1 << 0)
    static let toolCalling = ModelCapability(rawValue: 1 << 1)
    static let vision = ModelCapability(rawValue: 1 << 2)
    static let audio = ModelCapability(rawValue: 1 << 3)
    static let reasoning = ModelCapability(rawValue: 1 << 4)
    static let promptCaching = ModelCapability(rawValue: 1 << 5)

    static let all: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching]
}

/// Model reasoning configuration
struct ModelReasoningConfig: Codable {
    let type: ReasoningConfigType
    let defaultEffort: ReasoningEffort?
    let defaultBudget: Int?

    init(type: ReasoningConfigType, defaultEffort: ReasoningEffort? = nil, defaultBudget: Int? = nil) {
        self.type = type
        self.defaultEffort = defaultEffort
        self.defaultBudget = defaultBudget
    }
}

/// Reasoning configuration type
enum ReasoningConfigType: String, Codable {
    case effort // OpenAI, Vertex Gemini 3
    case budget // Anthropic, Vertex Gemini 2.5
    case toggle // Providers that support a simple on/off switch (e.g., Cerebras GLM)
    case none // xAI (not supported)
}

/// Token usage statistics
struct Usage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let cachedTokens: Int? // Prompt caching (Anthropic)

    var totalTokens: Int {
        inputTokens + outputTokens + (thinkingTokens ?? 0)
    }

    init(inputTokens: Int, outputTokens: Int, thinkingTokens: Int? = nil, cachedTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thinkingTokens = thinkingTokens
        self.cachedTokens = cachedTokens
    }
}
