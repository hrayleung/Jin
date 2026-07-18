import Foundation

/// Cerebras provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.cerebras.ai
/// - Endpoint: POST /v1/chat/completions
/// - Models: `qwen-3-235b-a22b-instruct-2507`, `zai-glm-4.7`, `gpt-oss-120b`
actor CerebrasAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability
    private let profile: OpenAICompatibleProfile

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        let profile = OpenAICompatibleProfile.profile(for: .cerebras) ?? .default
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.profile = profile
        self.capabilities = profile.capabilities
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // Cerebras does not support streaming with tool calling on reasoning models.
        let effectiveStreaming = profile.disablesStreamingWithTools
            ? (streaming && tools.isEmpty)
            : streaming

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: effectiveStreaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: effectiveStreaming,
            reasoningField: profile.reasoningField,
            networkManager: networkManager
        )
    }

    var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.cerebras.ai")
            .trimmed
        return stripTrailingV1(raw)
    }
}
