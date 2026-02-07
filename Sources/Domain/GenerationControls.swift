import Foundation

/// Generation controls for LLM requests
struct GenerationControls: Codable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var reasoning: ReasoningControls?
    var webSearch: WebSearchControls?
    var mcpTools: MCPToolsControls?
    /// How to process PDF attachments before sending to the model.
    /// `nil` means "default" (Native).
    var pdfProcessingMode: PDFProcessingMode?
    /// Image-generation specific controls for Gemini image models.
    var imageGeneration: ImageGenerationControls?
    var providerSpecific: [String: AnyCodable] = [:] // Escape hatch for provider-specific params

    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        reasoning: ReasoningControls? = nil,
        webSearch: WebSearchControls? = nil,
        mcpTools: MCPToolsControls? = nil,
        pdfProcessingMode: PDFProcessingMode? = nil,
        imageGeneration: ImageGenerationControls? = nil,
        providerSpecific: [String: AnyCodable] = [:]
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.reasoning = reasoning
        self.webSearch = webSearch
        self.mcpTools = mcpTools
        self.pdfProcessingMode = pdfProcessingMode
        self.imageGeneration = imageGeneration
        self.providerSpecific = providerSpecific
    }
}

/// Image-generation controls shared by Gemini (AI Studio) and Vertex AI.
struct ImageGenerationControls: Codable {
    /// `nil` defaults to `TEXT + IMAGE` for image-generation models.
    var responseMode: ImageResponseMode?
    var aspectRatio: ImageAspectRatio?
    /// Gemini 3 Pro Image supports 1K/2K/4K. Keep `nil` for model default.
    var imageSize: ImageOutputSize?
    /// Seed for reproducible image generation (where supported).
    var seed: Int?

    // Vertex-only extensions.
    var vertexPersonGeneration: VertexImagePersonGeneration?
    var vertexOutputMIMEType: VertexImageOutputMIMEType?
    var vertexCompressionQuality: Int?

    init(
        responseMode: ImageResponseMode? = nil,
        aspectRatio: ImageAspectRatio? = nil,
        imageSize: ImageOutputSize? = nil,
        seed: Int? = nil,
        vertexPersonGeneration: VertexImagePersonGeneration? = nil,
        vertexOutputMIMEType: VertexImageOutputMIMEType? = nil,
        vertexCompressionQuality: Int? = nil
    ) {
        self.responseMode = responseMode
        self.aspectRatio = aspectRatio
        self.imageSize = imageSize
        self.seed = seed
        self.vertexPersonGeneration = vertexPersonGeneration
        self.vertexOutputMIMEType = vertexOutputMIMEType
        self.vertexCompressionQuality = vertexCompressionQuality
    }

    var isEmpty: Bool {
        responseMode == nil
            && aspectRatio == nil
            && imageSize == nil
            && seed == nil
            && vertexPersonGeneration == nil
            && vertexOutputMIMEType == nil
            && vertexCompressionQuality == nil
    }
}

enum ImageResponseMode: String, Codable, CaseIterable {
    case textAndImage
    case imageOnly

    var displayName: String {
        switch self {
        case .textAndImage:
            return "Text + Image"
        case .imageOnly:
            return "Image only"
        }
    }

    var responseModalities: [String] {
        switch self {
        case .textAndImage:
            return ["TEXT", "IMAGE"]
        case .imageOnly:
            return ["IMAGE"]
        }
    }
}

enum ImageAspectRatio: String, Codable, CaseIterable {
    case ratio1x1 = "1:1"
    case ratio3x4 = "3:4"
    case ratio4x3 = "4:3"
    case ratio9x16 = "9:16"
    case ratio16x9 = "16:9"
    case ratio2x3 = "2:3"
    case ratio3x2 = "3:2"
    case ratio4x5 = "4:5"
    case ratio5x4 = "5:4"

    var displayName: String { rawValue }
}

enum ImageOutputSize: String, Codable, CaseIterable {
    case size1K = "1K"
    case size2K = "2K"
    case size4K = "4K"

    var displayName: String { rawValue }
}

enum VertexImagePersonGeneration: String, Codable, CaseIterable {
    case unspecified = "PERSON_GENERATION_UNSPECIFIED"
    case allowNone = "ALLOW_NONE"
    case allowAdult = "ALLOW_ADULT"
    case allowAll = "ALLOW_ALL"

    var displayName: String {
        switch self {
        case .unspecified:
            return "Default"
        case .allowNone:
            return "Don't allow people"
        case .allowAdult:
            return "Allow adults"
        case .allowAll:
            return "Allow all"
        }
    }
}

enum VertexImageOutputMIMEType: String, Codable, CaseIterable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case webp = "image/webp"

    var displayName: String {
        rawValue
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

enum PDFProcessingMode: String, Codable, CaseIterable {
    case native
    case mistralOCR
    case deepSeekOCR
    case macOSExtract

    var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .mistralOCR:
            return "Mistral OCR"
        case .deepSeekOCR:
            return "DeepSeek OCR (DeepInfra)"
        case .macOSExtract:
            return "macOS Extract"
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
    case xhigh // Extra high / max (OpenAI GPT-5.2, Anthropic Opus)

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
    var baseURL: String?
    var models: [ModelInfo]

    init(
        id: String,
        name: String,
        type: ProviderType,
        apiKey: String? = nil,
        serviceAccountJSON: String? = nil,
        baseURL: String? = nil,
        models: [ModelInfo] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.apiKey = apiKey
        self.serviceAccountJSON = serviceAccountJSON
        self.baseURL = baseURL
        self.models = models
    }
}

/// Provider type
enum ProviderType: String, Codable, CaseIterable {
    case openai
    case openrouter
    case anthropic
    case xai
    case deepseek
    case fireworks
    case cerebras
    case gemini
    case vertexai

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .anthropic: return "Anthropic"
        case .xai: return "xAI"
        case .deepseek: return "DeepSeek"
        case .fireworks: return "Fireworks"
        case .cerebras: return "Cerebras"
        case .gemini: return "Gemini (AI Studio)"
        case .vertexai: return "Vertex AI"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .openrouter:
            return "https://openrouter.ai/api/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .xai:
            return "https://api.x.ai/v1"
        case .deepseek:
            return "https://api.deepseek.com/v1"
        case .fireworks:
            return "https://api.fireworks.ai/inference/v1"
        case .cerebras:
            // OpenAI-compatible base URL per Cerebras docs.
            return "https://api.cerebras.ai/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
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
    static let nativePDF = ModelCapability(rawValue: 1 << 6)
    static let imageGeneration = ModelCapability(rawValue: 1 << 7)

    static let all: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration]
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
        serviceTier: String? = nil,
        inferenceGeo: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thinkingTokens = thinkingTokens
        self.cachedTokens = cachedTokens
        self.serviceTier = serviceTier
        self.inferenceGeo = inferenceGeo
    }
}
