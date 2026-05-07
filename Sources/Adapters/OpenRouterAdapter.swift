import Foundation

/// OpenRouter provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://openrouter.ai/api/v1
/// - Endpoint: POST /chat/completions
/// - Models: GET /models
/// - Async video models: GET /videos/models
actor OpenRouterAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .videoGeneration]

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
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(
                messages: messages,
                modelID: modelID,
                controls: controls
            )
        }

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
        OpenRouterProviderSupport.normalizedBaseURL(providerConfig.baseURL)
    }

    var openRouterHeaders: [String: String] {
        OpenRouterProviderSupport.appIdentityHeaders
    }
}
