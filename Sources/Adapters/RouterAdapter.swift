import Foundation

/// Router (Ramp) provider adapter.
///
/// Router is an LLM gateway that fronts Anthropic, OpenAI, xAI and Fireworks-hosted
/// open models behind one key. Unlike every other OpenAI-shaped gateway in Jin it is
/// **Responses-only**:
/// - `POST /v1/responses` — the sole completion route, OpenAI Responses schema
/// - `GET  /v1/models`   — OpenAI model-list shape plus a rich `router` metadata object
/// - `POST /v1/chat/completions` — **404s**, "not supported yet"
///
/// So this adapter owns no wire code of its own: it delegates the whole send to
/// `OpenAIAdapter`, which already POSTs to `"\(baseURL)/responses"`.
///
/// Docs: https://docs.router.com/api/endpoint
actor RouterAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    let apiKey: String
    let networkManager: NetworkManager
    private let responsesDelegate: OpenAIAdapter

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager

        // `OpenAIAdapter.baseURL` is `providerConfig.baseURL` verbatim and it POSTs to
        // "\(baseURL)/responses", so this delegate hits exactly
        // https://api.router.com/v1/responses.
        //
        // The delegate config's `type` MUST stay `.router`. Every OpenAI-platform-only
        // wire field — `service_tier`, `prompt_cache_key` / `prompt_cache_retention`,
        // `reasoning.summary`, `reasoning.mode`, `reasoning.context`, and the hosted
        // `/files` upload behind native PDF — is suppressed by a provider-type gate
        // (`usesNativeOpenAIPlatform`). Rebuilding this with `type: .openai` would
        // silently re-enable all of them; Router has no upload API at all, and reports
        // `reasoning.summary.request_parameter_supported: false` on every model.
        let delegateConfig = ProviderConfig(
            id: providerConfig.id,
            name: providerConfig.name,
            type: .router,
            baseURL: baseURLValue(for: providerConfig),
            models: providerConfig.models
        )
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
        try await responsesDelegate.sendMessage(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
    }

    nonisolated func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateToolToOpenAIFormat)
    }

    var baseURL: String {
        baseURLValue(for: providerConfig)
    }
}

/// Normalizes a user-entered Router base URL. Router appends both of its routes to a
/// base that already carries `/v1`, and the docs are explicit that the `/v1` has to
/// stay — so a bare host gets it added back rather than 404ing on `/responses`.
private func baseURLValue(for providerConfig: ProviderConfig) -> String {
    let fallback = ProviderType.router.defaultBaseURL ?? "https://api.router.com/v1"
    let raw = (providerConfig.baseURL ?? fallback).trimmed
    guard !raw.isEmpty else { return fallback }

    let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    if trimmed.lowercased().hasSuffix("/v1") {
        return trimmed
    }
    if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
        return "\(trimmed)/v1"
    }
    return trimmed
}
