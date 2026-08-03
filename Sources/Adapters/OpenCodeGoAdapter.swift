import Foundation

/// OpenCode Go provider adapter.
///
/// OpenCode Go is the flat-fee subscription tier (open-weight models), served on the
/// `/zen/go/v1` path — distinct from pay-as-you-go OpenCode Zen on `/zen/v1`.
///
/// Routes requests to the correct endpoint format based on model ID, following the
/// per-model endpoint table published at https://opencode.ai/docs/go/:
/// - Claude, MiniMax, and Qwen models → Anthropic-compatible `/messages`
///   (see `usesAnthropicMessagesEndpoint(_:)`)
/// - GPT-5.6 Luna → OpenAI **Responses** `/responses`
///   (see `usesOpenAIResponsesEndpoint(_:)`)
/// - DeepSeek, GLM, Kimi, MiMo, Grok, Hy3, … → OpenAI-compatible `/chat/completions`
///
/// Docs: https://opencode.ai/docs/go/
actor OpenCodeGoAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    let apiKey: String
    let networkManager: NetworkManager
    private let anthropicDelegate: AnthropicAdapter
    private let responsesDelegate: OpenAIAdapter

    static let hardcodedBaseURL = "https://opencode.ai/zen/go/v1"
    static let anthropicModelIDs: Set<String> = [
        "claude-fable-5",
        "claude-opus-5",
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

    /// Exact model IDs OpenCode Go serves via the OpenAI **Responses** `/responses` endpoint.
    /// opencode.ai/docs/go's per-model endpoint table (page updated 2026-08-02) is the
    /// authority: `gpt-5.6-luna` is the only Go model mapped to `@ai-sdk/openai` +
    /// `/zen/go/v1/responses`; every other OpenAI-shaped model is `@ai-sdk/openai-compatible`
    /// + `/chat/completions`. A live unauthenticated probe confirms `/responses` exists on the
    /// Go gateway and accepts this model (it answers `AuthError`), while rejecting the
    /// Anthropic-format models outright ("Model minimax-m3 is not supported for format
    /// openai"). `/chat/completions` is not a viable fallback: OpenAI rejects function tools
    /// combined with reasoning for the GPT-5.6 family there and directs callers to
    /// `/v1/responses`, so every tool-enabled send would fail. Matched by exact ID — never by
    /// prefix, since the sibling Sol/Terra tiers are not on OpenCode Go.
    static let openAIResponsesModelIDs: Set<String> = [
        "gpt-5.6-luna",
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
        // `OpenAIAdapter` POSTs to "\(baseURL)/responses" and its `baseURL` is
        // `providerConfig.baseURL`, so this delegate hits exactly
        // https://opencode.ai/zen/go/v1/responses. The delegate config's `type` MUST stay
        // `.opencodeGo`: the OpenAI-platform-only wire fields (`service_tier`,
        // `prompt_cache_*`, `reasoning.summary/.mode/.context`, `text.verbosity`, the hosted
        // `/files` upload behind native PDF, and `code_interpreter`) are all suppressed by
        // provider-type gates. Rebuilding this config with `type: .openai` would silently
        // re-enable every one of them against a gateway that rejects unknown fields.
        self.responsesDelegate = OpenAIAdapter(
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

        if Self.usesOpenAIResponsesEndpoint(modelID) {
            return try await responsesDelegate.sendMessage(
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
