import Foundation

/// OpenCode Go provider adapter.
///
/// OpenCode Go is the flat-fee subscription tier (open-weight models), served on the
/// `/zen/go/v1` path — distinct from pay-as-you-go OpenCode Zen on `/zen/v1`.
///
/// Routes requests to the correct endpoint format based on model ID
/// (see `usesAnthropicMessagesEndpoint(_:)`):
/// - Claude, MiniMax, and Qwen models → Anthropic-compatible `/messages`
/// - DeepSeek, GLM, Kimi, MiMo, and other models → OpenAI-compatible `/chat/completions`
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
        "claude-fable-5",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-opus-4-5",
        "claude-opus-4-1",
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "claude-sonnet-4-5",
        "claude-sonnet-4",
        "claude-haiku-4-5",
        "claude-3-5-haiku",
    ]

    /// Exact model IDs OpenCode Go serves via the Anthropic-style `/messages` endpoint
    /// (Claude, plus the MiniMax and Qwen families per opencode.ai/docs/go + models.dev
    /// `opencode-go` → `@ai-sdk/anthropic`). Matched by exact ID — never by prefix — so a
    /// new/unknown `minimax-*`/`qwen*` ID does not silently route to the wrong endpoint.
    static let anthropicMessagesModelIDs: Set<String> = anthropicModelIDs.union([
        "minimax-m3",
        "minimax-m2.7",
        "minimax-m2.5",
        "minimax-m2.5-free",
        "qwen3.7-max",
        "qwen3.7-plus",
        "qwen3.6-plus",
        "qwen3.5-plus",
    ])

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
        if Self.usesAnthropicMessagesEndpoint(modelID) {
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
