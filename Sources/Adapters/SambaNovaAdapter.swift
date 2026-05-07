import Foundation

/// SambaNova Cloud provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.sambanova.ai/v1
/// - Endpoint: POST /v1/chat/completions
/// - Models: `MiniMax-M2.5`, `DeepSeek-V3.1`, `gpt-oss-120b`, ...
///
/// SambaNova-specific parameters:
/// - `chat_template_kwargs: {"enable_thinking": true/false}` — toggles reasoning for
///    DeepSeek-V3.1 and Qwen3 models.
/// - `reasoning_effort: "low"/"medium"/"high"` — controls reasoning depth for gpt-oss-120b.
/// - Reasoning content is returned in `<think>` tags within content deltas.
actor SambaNovaAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

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

    var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.sambanova.ai")
            .trimmed
        return stripTrailingV1(raw)
    }
}
