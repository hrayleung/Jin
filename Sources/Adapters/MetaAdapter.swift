import Foundation

/// Meta Model API provider adapter (OpenAI-compatible **Responses** API).
///
/// Endpoints:
/// - GET  /models
/// - POST /responses
/// - POST /files  (purpose=`user_data`, for large video/PDF/audio)
///
/// Muse Spark also speaks Chat Completions and Anthropic Messages on the same host;
/// Jin uses Responses for multimodal input (image/PDF/video), web_search grounding,
/// tool loops, and reasoning continuity.
///
/// Request quirks (verified against dev.meta.ai docs, 2026-08):
/// - Reasoning is always-on; never send `reasoning.effort: "none"` (HTTP 400).
/// - Prefer `temperature` **or** `top_p`, not both.
/// - Token cap is `max_output_tokens`.
/// - Strict validation: omit OpenAI-only fields (verbosity, stop, web_search_options, …).
///
/// Docs: https://dev.meta.ai/docs
/// Default base URL: https://api.meta.ai/v1
actor MetaAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [
        .streaming, .toolCalling, .vision, .videoInput, .nativePDF, .reasoning, .promptCaching
    ]

    let networkManager: NetworkManager
    let apiKey: String

    /// Inline media larger than this is uploaded via Files API and referenced by `file_id`.
    /// Meta documents a 50 MB inline limit; stay under it with a safety margin.
    static let inlineMediaByteLimit = 40 * 1_024 * 1_024

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        try await sendResponsesConversation(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(MetaResponsesInputSupport.responsesToolDefinition)
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.meta.defaultBaseURL ?? "https://api.meta.ai/v1")
            .trimmed
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        if trimmed.lowercased().hasSuffix("/v1") {
            return trimmed
        }

        return "\(trimmed)/v1"
    }
}
