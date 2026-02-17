import Foundation

/// Generation controls for LLM requests.
///
/// This is the top-level configuration struct. Individual control types
/// are defined in their own focused files:
/// - `ContextCacheControls.swift` -- prompt caching
/// - `ReasoningControls.swift` -- thinking/reasoning
/// - `WebSearchAndToolControls.swift` -- web search, MCP tools, PDF processing
/// - `XAIMediaGenerationControls.swift` -- xAI image/video generation
/// - `GoogleMediaGenerationControls.swift` -- Gemini/Vertex image/video generation
/// - `ProviderTypes.swift` -- ProviderType, ProviderConfig, ModelInfo, Usage
struct GenerationControls: Codable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var reasoning: ReasoningControls?
    var webSearch: WebSearchControls?
    var mcpTools: MCPToolsControls?
    var contextCache: ContextCacheControls?
    var pdfProcessingMode: PDFProcessingMode?
    var imageGeneration: ImageGenerationControls?
    var xaiImageGeneration: XAIImageGenerationControls?
    var xaiVideoGeneration: XAIVideoGenerationControls?
    var googleVideoGeneration: GoogleVideoGenerationControls?
    var providerSpecific: [String: AnyCodable] = [:]

    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        reasoning: ReasoningControls? = nil,
        webSearch: WebSearchControls? = nil,
        mcpTools: MCPToolsControls? = nil,
        contextCache: ContextCacheControls? = nil,
        pdfProcessingMode: PDFProcessingMode? = nil,
        imageGeneration: ImageGenerationControls? = nil,
        xaiImageGeneration: XAIImageGenerationControls? = nil,
        xaiVideoGeneration: XAIVideoGenerationControls? = nil,
        googleVideoGeneration: GoogleVideoGenerationControls? = nil,
        providerSpecific: [String: AnyCodable] = [:]
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.reasoning = reasoning
        self.webSearch = webSearch
        self.mcpTools = mcpTools
        self.contextCache = contextCache
        self.pdfProcessingMode = pdfProcessingMode
        self.imageGeneration = imageGeneration
        self.xaiImageGeneration = xaiImageGeneration
        self.xaiVideoGeneration = xaiVideoGeneration
        self.googleVideoGeneration = googleVideoGeneration
        self.providerSpecific = providerSpecific
    }
}
