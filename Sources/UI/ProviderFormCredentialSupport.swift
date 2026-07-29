import Foundation

extension ProviderFormSupport {
    enum CredentialKind: Equatable {
        case apiKey
        case serviceAccountJSON
    }

    struct OpenRouterUsagePresentation: Equatable {
        let isRefreshDisabled: Bool
        let statusLabel: String
        let hintText: String
    }

    static func credentialKind(for providerType: ProviderType) -> CredentialKind {
        switch providerType {
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .xai,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .databricks, .morphllm, .opencodeGo, .gemini, .zyphra, .meta, .kimiForCoding:
            return .apiKey
        case .vertexai:
            return .serviceAccountJSON
        }
    }

    static func apiKeyFieldTitle(for providerType: ProviderType?) -> String {
        providerType == .githubCopilot ? "GitHub Token" : "API Key"
    }

    static func apiKeyRevealHelp(for providerType: ProviderType?) -> String {
        providerType == .githubCopilot ? "Show GitHub token" : "Show API key"
    }

    static func apiKeyConcealHelp(for providerType: ProviderType?) -> String {
        providerType == .githubCopilot ? "Hide GitHub token" : "Hide API key"
    }

    static func providerSetupCallout(for providerType: ProviderType) -> String? {
        switch providerType {
        default:
            return nil
        }
    }

    static func providerDetailsText(for providerType: ProviderType) -> String? {
        switch providerType {
        case .openaiWebSocket:
            return "Keeps a persistent connection to `/v1/responses`. Only one response can be in flight per connection."
        case .cloudflareAIGateway:
            return "Recommended: use a Cloudflare API Token (BYOK mode). Keep the `/compat` base URL, configure upstream provider keys in AI Gateway, then use model IDs like `openai/gpt-5` or `anthropic/claude-sonnet-4.5`."
        case .zhipuCodingPlan:
            return "Use `https://open.bigmodel.cn/api/coding/paas/v4` instead of the generic `/api/paas/v4`. Recommended models: `glm-5.2`, `glm-5`, `glm-4.7`."
        case .minimax:
            return "International endpoint: `https://api.minimax.io/v1`. Recommended models: `MiniMax-M2.7`, `MiniMax-M2.5`."
        case .minimaxCodingPlan:
            return "Uses MiniMax's unified OpenAI-compatible endpoint (international: `https://api.minimax.io/v1`; China: `https://api.minimaxi.com/v1`). Supports both pay-as-you-go and Token Plan keys (Token Plan keys start with `sk-cp-`); the same key also works on MiniMax's `/anthropic` endpoint."
        case .mimoTokenPlanOpenAI:
            return "Use the OpenAI-compatible Token Plan Base URL from the MiMo subscription page. The Singapore default is `https://token-plan-sgp.xiaomimimo.com/v1`; Token Plan keys start with `tp-`."
        case .mimoTokenPlanAnthropic:
            return "Use the Anthropic-compatible Token Plan Base URL from the MiMo subscription page. Jin accepts Xiaomi's displayed `/anthropic` URL and sends requests to `/anthropic/v1/messages`; Token Plan keys start with `tp-`."
        case .kimiForCoding:
            return "Anthropic-compatible endpoint at `https://api.kimi.com/coding` (requests go to `/v1/messages`). Use an API key from the Kimi Code Console. Models: `k3`, `kimi-for-coding`, `kimi-for-coding-highspeed`."
        case .databricks:
            return "Use a Databricks workspace personal access token (starts with `dapi…`, from Settings → Developer → Access tokens — not an account-level or narrow-scoped token, or you'll get a 403 `model-serving` scope error). The Base URL selects the surface, auto-detected: (1) Foundation Model APIs — workspace host `https://dbc-xxxx.cloud.databricks.com`; Jin queries `/serving-endpoints/chat/completions` and lists models via `/api/2.0/serving-endpoints` (e.g. `databricks-claude-sonnet-4-6`). (2) Unity AI Gateway, your own OpenAI key — base `https://dbc-xxxx.cloud.databricks.com/ai-gateway/openai/v1`. (3) Unity AI Gateway, your own Anthropic key — base `https://dbc-xxxx.cloud.databricks.com/ai-gateway/anthropic/v1`. For gateway modes, Fetch Models offers a curated set of current models (Databricks doesn't expose your provider's allowed list) — remove any your gateway rejects, or add others by ID. The provider service defaults to `workspace.default.<openai|anthropic>`; if yours lives elsewhere, append `?service=<catalog>.<schema>.<name>` to the Base URL (e.g. `…/ai-gateway/openai/v1?service=main.default.openai_prod`)."
        case .githubCopilot:
            return "Uses GitHub Models at `https://models.github.ai/inference`. Configure a GitHub token with GitHub Models access."
        default:
            return nil
        }
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }

    static func normalizedBaseURL(_ baseURL: String, providerType: ProviderType) -> String? {
        guard providerType != .vertexai else { return nil }
        return normalizedOptionalString(baseURL)
    }

    static func baseURLForEditing(_ baseURL: String, defaultBaseURL: String) -> String {
        normalizedOptionalString(baseURL) ?? defaultBaseURL
    }

    static func normalizedIconID(_ iconID: String?) -> String? {
        normalizedOptionalString(iconID)
    }

    static func isAddDisabled(
        providerType: ProviderType,
        name: String,
        apiKey: String,
        serviceAccountJSON: String,
        isSaving: Bool
    ) -> Bool {
        guard normalizedOptionalString(name) != nil, !isSaving else { return true }
        return isCredentialMissing(
            for: credentialKind(for: providerType),
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    static func isCredentialEmpty(
        providerType: ProviderType?,
        apiKey: String,
        serviceAccountJSON: String
    ) -> Bool {
        guard let providerType else { return true }
        return isCredentialMissing(
            for: credentialKind(for: providerType),
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    static func isFetchModelsDisabled(
        isFetchingModels: Bool,
        providerType: ProviderType?,
        apiKey: String,
        serviceAccountJSON: String
    ) -> Bool {
        isFetchingModels || isCredentialActionDisabled(
            providerType: providerType,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    static func isTestConnectionDisabled(
        providerType: ProviderType?,
        isTesting: Bool,
        apiKey: String,
        serviceAccountJSON: String
    ) -> Bool {
        isTesting || isCredentialActionDisabled(
            providerType: providerType,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    static func openRouterUsagePresentation(
        apiKey: String,
        status: OpenRouterUsageStatus
    ) -> OpenRouterUsagePresentation {
        let hasAPIKey = normalizedOptionalString(apiKey) != nil

        let statusLabel: String
        switch status {
        case .idle, .failure:
            statusLabel = "Not observed"
        case .loading:
            statusLabel = "Checking"
        case .observed:
            statusLabel = "Observed"
        }

        let hintText: String
        switch status {
        case .idle:
            hintText = hasAPIKey ? "Usage not fetched yet." : "Enter an API key to check usage."
        case .loading:
            hintText = "Fetching current key usage..."
        case .observed:
            hintText = "No usage data returned for this key."
        case .failure:
            hintText = "Failed to fetch usage for this key."
        }

        return OpenRouterUsagePresentation(
            isRefreshDisabled: !hasAPIKey || status == .loading,
            statusLabel: statusLabel,
            hintText: hintText
        )
    }

    private static func isCredentialMissing(
        for kind: CredentialKind,
        apiKey: String,
        serviceAccountJSON: String
    ) -> Bool {
        switch kind {
        case .apiKey:
            return normalizedOptionalString(apiKey) == nil
        case .serviceAccountJSON:
            return normalizedOptionalString(serviceAccountJSON) == nil
        }
    }

    private static func isCredentialActionDisabled(
        providerType: ProviderType?,
        apiKey: String,
        serviceAccountJSON: String
    ) -> Bool {
        guard let providerType else { return true }

        let kind = credentialKind(for: providerType)
        return isCredentialMissing(
            for: kind,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }
}
