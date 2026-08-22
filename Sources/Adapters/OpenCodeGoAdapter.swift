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
/// - GPT-5.6 Luna → OpenAI **Responses** `/responses` via `OpenAIAdapter`
///   (see `usesOpenAIResponsesEndpoint(_:)`)
/// - Muse Spark 1.2 / 1.2 Contributor → Meta-shaped **Responses** `/responses`
///   via `MetaAdapter` so encrypted reasoning is requested, persisted, and
///   replayed across tool continuations (see `usesMuseSparkResponsesEndpoint(_:)`)
/// - DeepSeek, GLM, Kimi, MiMo, Grok, Hy3, Ox Alpha Free, … → OpenAI-compatible `/chat/completions`
///
/// Docs: https://opencode.ai/docs/go/
actor OpenCodeGoAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    let apiKey: String
    let networkManager: NetworkManager
    private let anthropicDelegate: AnthropicAdapter
    private let responsesDelegate: OpenAIAdapter
    private let museSparkDelegate: MetaAdapter

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
        "qwen3.8-max",
        "qwen3.7-max",
        "qwen3.7-plus",
        "qwen3.6-plus",
        "qwen3.5-plus",
    ])

    /// Exact model IDs OpenCode Go serves via the OpenAI **Responses** `/responses` endpoint.
    /// opencode.ai/docs/go maps `gpt-5.6-luna` and Muse Spark to `@ai-sdk/openai` +
    /// `/zen/go/v1/responses`. Live `/zen/go/v1/models` (2026-08-20) lists both
    /// `muse-spark-1.2` and `muse-spark-1.2-contributor`; a dummy-key probe of `/responses`
    /// answers `AuthError` (model accepted) rather than "not supported for format openai"
    /// (the rejection MiniMax gets there). `muse-spark-1.1` is not served
    /// ("Model muse-spark-1.1 is not supported"). `/chat/completions` is not a viable
    /// fallback for Luna: OpenAI rejects function tools combined with reasoning for the
    /// GPT-5.6 family there. Matched by exact ID — never by prefix.
    static let openAIResponsesModelIDs: Set<String> = [
        "gpt-5.6-luna",
        "muse-spark-1.2",
        "muse-spark-1.2-contributor",
    ]

    /// Exact model IDs on the OpenAI-compatible `/chat/completions` path whose upstream
    /// rejects any non-default `temperature` (HTTP 400: "invalid temperature: only 1 is
    /// allowed for this model", or the mode-locked 1.0/0.6 pair for K2.5/K2.6).
    ///
    /// Sources (exact IDs, never prefix):
    /// - models.dev `opencode-go` marks `kimi-k3` and `kimi-k2.7-code` as `temperature: false`
    /// - Moonshot docs: K3 / K2.7 Code are fixed at 1.0; K2.5 / K2.6 are fixed at 1.0
    ///   (thinking) or 0.6 (instant) — "Do not pass temperature explicitly"
    ///
    /// `gpt-5.6-luna` is also `temperature: false` on models.dev, but it is handled by the
    /// Responses sampling gate (`supportsOpenAIResponsesSamplingParameters`) rather than this
    /// set, because it never reaches `buildOpenAIRequest`.
    static let temperatureUnsupportedChatCompletionsModelIDs: Set<String> = [
        "kimi-k3",
        "kimi-k2.7-code",
        "kimi-k2.6",
        "kimi-k2.5",
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
        // Muse Spark on Go is Meta's model behind an OpenAI-shaped `/responses`
        // gateway. The generic OpenAIAdapter path neither requests
        // `reasoning.encrypted_content` nor replays the resulting reasoning item
        // before `function_call` / `function_call_output`, so tool continuations
        // lose CoT. `MetaAdapter` supplies that request/parse/replay while the
        // config `type` stays `.opencodeGo` so cache keys, hosted `/files`, and
        // web_search stay gated off.
        self.museSparkDelegate = MetaAdapter(
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

        if Self.usesMuseSparkResponsesEndpoint(modelID) {
            return try await museSparkDelegate.sendMessage(
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
