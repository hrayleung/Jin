import Foundation

/// DeepSeek official provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.deepseek.com
/// - Endpoint: POST /chat/completions
/// - Models: `deepseek-chat`, `deepseek-reasoner`, `deepseek-v3.2-exp`, `deepseek-v4-flash`, `deepseek-v4-pro`, ...
actor DeepSeekAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .reasoning]

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

    var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.deepseek.com")
            .trimmed
        return stripTrailingV1(raw)
    }
}
