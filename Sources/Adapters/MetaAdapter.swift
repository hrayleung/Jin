import Foundation

/// Meta Model API provider adapter (OpenAI-compatible Chat Completions API).
///
/// Endpoints:
/// - GET  /models
/// - POST /chat/completions
///
/// The Meta Model API (public preview, 2026-07) also speaks the OpenAI Responses and
/// Anthropic Messages protocols on the same base URL; Jin uses the Chat Completions
/// surface. Auth is `Authorization: Bearer` on every protocol.
///
/// Request quirks (verified against dev.meta.ai docs, 2026-07-11):
/// - Strict validation: unknown fields and `logprobs: true` return HTTP 400.
/// - Muse Spark is tuned for the default sampling settings; set `temperature` OR
///   `top_p`, never both.
/// - Reasoning is always-on; `reasoning_effort: "none"` returns HTTP 400, so disabling
///   reasoning omits the field entirely.
///
/// Docs: https://dev.meta.ai/docs
/// Default base URL: https://api.meta.ai/v1
actor MetaAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .reasoning, .vision]

    let networkManager: NetworkManager
    let apiKey: String

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
        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
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
