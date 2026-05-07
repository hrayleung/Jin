import Foundation

/// Fireworks provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.fireworks.ai/inference/v1
/// - Endpoint: POST /chat/completions
/// - Model listing: GET /v1/accounts/fireworks/models?filter=supports_serverless=true
/// - Models: `fireworks/qwen3p6-plus`, `accounts/fireworks/models/deepseek-v4-pro`,
///   `fireworks/deepseek-v3p2`, ...
actor FireworksAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

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
            reasoningField: .reasoningContent,
            networkManager: networkManager
        )
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://api.fireworks.ai/inference/v1")
            .trimmed
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
}
