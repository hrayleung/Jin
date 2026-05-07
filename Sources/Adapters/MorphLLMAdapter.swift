import Foundation

/// MorphLLM provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs: https://docs.morphllm.com
/// - Base URL: https://api.morphllm.com/v1
/// - Endpoint: POST /v1/chat/completions
/// - Models: `morph-v3-fast` (10,500 tok/s), `morph-v3-large` (98% accuracy), `auto` (recommended)
///
/// Fast Apply models are specialized for code editing — they accept standard chat completions
/// format and return merged code. No tool calling support.
actor MorphLLMAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming]

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
            streaming: streaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoning,
            networkManager: networkManager
        )
    }

    var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.morphllm.com")
            .trimmed
        return stripTrailingV1(raw)
    }
}
