import Foundation

/// OpenCode Zen provider adapter.
///
/// Routes requests to the correct endpoint format based on model ID:
/// - Cataloged non-Claude models → OpenAI-compatible `/chat/completions`
/// - Claude models manually added by ID → Anthropic-compatible `/messages`
///
/// Docs: https://opencode.ai/docs/zen/
actor OpenCodeGoAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    let apiKey: String
    let networkManager: NetworkManager
    private let anthropicDelegate: AnthropicAdapter

    static let hardcodedBaseURL = "https://opencode.ai/zen/v1"
    static let anthropicModelIDs: Set<String> = [
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-opus-4-5",
        "claude-opus-4-1",
        "claude-sonnet-4-6",
        "claude-sonnet-4-5",
        "claude-sonnet-4",
        "claude-haiku-4-5",
        "claude-3-5-haiku",
    ]

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager

        let delegateConfig = ProviderConfig(
            id: providerConfig.id,
            name: providerConfig.name,
            type: .opencodeGo,
            baseURL: Self.hardcodedBaseURL,
            models: providerConfig.models
        )
        self.anthropicDelegate = AnthropicAdapter(
            providerConfig: delegateConfig,
            apiKey: apiKey,
            networkManager: networkManager
        )
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if Self.isAnthropicModel(modelID) {
            return try await anthropicDelegate.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: streaming
            )
        }

        let request = try buildOpenAIRequest(
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
}
