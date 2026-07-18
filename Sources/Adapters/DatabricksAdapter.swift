import Foundation

/// Databricks Model Serving provider adapter (OpenAI-compatible Chat Completions API).
///
/// Databricks is workspace-scoped: the user configures their workspace host (for example
/// `https://dbc-xxxx.cloud.databricks.com` or the full `.../serving-endpoints` URL). Jin
/// normalizes that to the workspace root and derives two routes:
///
/// - Chat:  POST `{workspace}/serving-endpoints/chat/completions` (model = serving-endpoint
///          name, e.g. `databricks-claude-sonnet-4-6`). Standard OpenAI body + SSE.
/// - Models: GET `{workspace}/api/2.0/serving-endpoints` (native Databricks API; there is no
///          OpenAI `/models` route). Chat endpoints are those with `task == "llm/v1/chat"`.
///
/// Auth is a Databricks personal access token (or M2M OAuth token) sent as
/// `Authorization: Bearer <token>`. Reasoning models accept `reasoning_effort`
/// (`low`/`medium`/`high`).
///
/// Docs: docs.databricks.com/machine-learning/foundation-model-apis/api-reference
actor DatabricksAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability
    private let profile: OpenAICompatibleProfile

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        let profile = OpenAICompatibleProfile.profile(for: .databricks) ?? .chatWithVision
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
            reasoningField: profile.reasoningField,
            networkManager: networkManager
        )
    }

    /// The configured base URL, trimmed (falling back to the provider default).
    var configuredBaseURL: String {
        (providerConfig.baseURL?.trimmedNonEmpty
            ?? ProviderType.databricks.defaultBaseURL
            ?? "https://dbc-00000000-0000.cloud.databricks.com").trimmed
    }

    /// The Databricks workspace root (scheme + host [+ port]), derived from the configured base URL
    /// by discarding any `/serving-endpoints` or `/ai-gateway/…` path the user pasted.
    var workspaceRoot: String {
        DatabricksGateway.workspaceRoot(from: configuredBaseURL)
    }

    /// Whether this config queries a Unity AI Gateway OpenAI provider service (BYOK), rather than
    /// Foundation Model APIs. (Anthropic gateway configs are routed to `AnthropicAdapter` by
    /// `ProviderManager` and never reach this adapter.)
    var isOpenAIGateway: Bool {
        DatabricksGateway.isOpenAIGateway(configuredBaseURL)
    }

    /// The `Databricks-Model-Provider-Service` value for AI Gateway requests, or nil for FMAPI.
    var gatewayProviderService: String? {
        DatabricksGateway.providerServiceName(from: configuredBaseURL)
    }

    /// OpenAI-compatible base path for chat completions.
    ///
    /// - Foundation Model APIs live under `{workspace}/serving-endpoints`.
    /// - AI Gateway OpenAI provider services use the native OpenAI surface
    ///   `{workspace}/ai-gateway/openai/v1` (chat completions), with the provider-service header.
    var openAICompatibleBase: String {
        isOpenAIGateway
            ? "\(workspaceRoot)/ai-gateway/openai/v1"
            : "\(workspaceRoot)/serving-endpoints"
    }

    /// OpenAI-compatible chat completions endpoint.
    var chatCompletionsURLString: String {
        "\(openAICompatibleBase)/chat/completions"
    }

    /// Foundation Model APIs serving-endpoints listing (used for validation + model discovery
    /// outside AI Gateway mode).
    var servingEndpointsListURLString: String {
        "\(workspaceRoot)/api/2.0/serving-endpoints"
    }
}
