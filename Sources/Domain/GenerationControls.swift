import Foundation

/// Generation controls for LLM requests.
///
/// This is the top-level configuration struct. Individual control types
/// are defined in their own focused files:
/// - `ContextCacheControls.swift` -- prompt caching
/// - `ReasoningControls.swift` -- thinking/reasoning
/// - `WebSearchAndToolControls.swift` -- web search, MCP tools, PDF processing
/// - `OpenAIServiceTier.swift` -- OpenAI `service_tier` (priority/flex/default/scale)
/// - `AnthropicSpeed.swift` -- Anthropic `speed` (fast mode on Opus 4.6/4.7)
/// - `OpenAIImageGenerationControls.swift` -- OpenAI image generation
/// - `XAIMediaGenerationControls.swift` -- xAI image/video generation
/// - `GoogleMediaGenerationControls.swift` -- Gemini/Vertex image/video generation
/// - `OpenRouterVideoGenerationControls.swift` -- OpenRouter video generation
/// - `TogetherVideoGenerationControls.swift` -- Together AI video generation
/// - `ProviderTypes.swift` -- ProviderType, ProviderConfig, ModelInfo, Usage
struct GenerationControls: Codable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var reasoning: ReasoningControls?
    /// OpenAI Responses API `text.verbosity` (low/medium/high).
    var textVerbosity: TextVerbosity?
    var webSearch: WebSearchControls?
    var openAIServiceTier: OpenAIServiceTier?
    var anthropicSpeed: AnthropicSpeed?
    var searchPlugin: SearchPluginControls?
    var mcpTools: MCPToolsControls?
    var contextCache: ContextCacheControls?
    var pdfProcessingMode: PDFProcessingMode?
    var firecrawlPDFParserMode: FirecrawlPDFParserMode?
    var imageGeneration: ImageGenerationControls?
    var openaiImageGeneration: OpenAIImageGenerationControls?
    var xaiImageGeneration: XAIImageGenerationControls?
    var xaiVideoGeneration: XAIVideoGenerationControls?
    var googleVideoGeneration: GoogleVideoGenerationControls?
    var openRouterVideoGeneration: OpenRouterVideoGenerationControls?
    var togetherVideoGeneration: TogetherVideoGenerationControls?
    var googleMaps: GoogleMapsControls?
    var codeExecution: CodeExecutionControls?
    var providerSpecific: [String: AnyCodable] = [:]

    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        reasoning: ReasoningControls? = nil,
        textVerbosity: TextVerbosity? = nil,
        webSearch: WebSearchControls? = nil,
        openAIServiceTier: OpenAIServiceTier? = nil,
        anthropicSpeed: AnthropicSpeed? = nil,
        searchPlugin: SearchPluginControls? = nil,
        mcpTools: MCPToolsControls? = nil,
        contextCache: ContextCacheControls? = nil,
        pdfProcessingMode: PDFProcessingMode? = nil,
        firecrawlPDFParserMode: FirecrawlPDFParserMode? = nil,
        imageGeneration: ImageGenerationControls? = nil,
        openaiImageGeneration: OpenAIImageGenerationControls? = nil,
        xaiImageGeneration: XAIImageGenerationControls? = nil,
        xaiVideoGeneration: XAIVideoGenerationControls? = nil,
        googleVideoGeneration: GoogleVideoGenerationControls? = nil,
        openRouterVideoGeneration: OpenRouterVideoGenerationControls? = nil,
        togetherVideoGeneration: TogetherVideoGenerationControls? = nil,
        googleMaps: GoogleMapsControls? = nil,
        codeExecution: CodeExecutionControls? = nil,
        providerSpecific: [String: AnyCodable] = [:]
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.reasoning = reasoning
        self.textVerbosity = textVerbosity
        self.webSearch = webSearch
        self.openAIServiceTier = openAIServiceTier
        self.anthropicSpeed = anthropicSpeed
        self.searchPlugin = searchPlugin
        self.mcpTools = mcpTools
        self.contextCache = contextCache
        self.pdfProcessingMode = pdfProcessingMode
        self.firecrawlPDFParserMode = firecrawlPDFParserMode
        self.imageGeneration = imageGeneration
        self.openaiImageGeneration = openaiImageGeneration
        self.xaiImageGeneration = xaiImageGeneration
        self.xaiVideoGeneration = xaiVideoGeneration
        self.googleVideoGeneration = googleVideoGeneration
        self.openRouterVideoGeneration = openRouterVideoGeneration
        self.togetherVideoGeneration = togetherVideoGeneration
        self.googleMaps = googleMaps
        self.codeExecution = codeExecution
        self.providerSpecific = providerSpecific
    }
}
