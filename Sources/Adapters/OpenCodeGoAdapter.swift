import Foundation

/// OpenCode Go provider adapter.
///
/// Routes requests to the correct endpoint format based on model ID:
/// - DeepSeek V4 Pro/Flash, GLM-5, Kimi K2.5/K2.6, MiMo V2.5/V2.5 Pro → OpenAI-compatible `/chat/completions`
/// - MiniMax M2.7/M2.5 → Anthropic-compatible `/messages`
///
/// Docs: https://opencode.ai/docs/go/
actor OpenCodeGoAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    let apiKey: String
    let networkManager: NetworkManager
    private let anthropicDelegate: AnthropicAdapter

    static let hardcodedBaseURL = "https://opencode.ai/zen/go/v1"
    static let anthropicModelIDs: Set<String> = [
        "minimax-m2.7",
        "minimax-m2.5",
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
