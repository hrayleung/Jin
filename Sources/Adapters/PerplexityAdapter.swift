import Foundation

/// Perplexity Sonar (OpenAI-compatible Chat Completions)
actor PerplexityAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    /// Perplexity supports streaming, vision, and web-grounded search. Function calling is OpenAI-compatible.
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

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.perplexity.defaultBaseURL ?? "https://api.perplexity.ai")
            .trimmed
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
}
