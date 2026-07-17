import Foundation

/// Helpers for Databricks Unity AI Gateway routing.
///
/// A Databricks provider config's base URL selects the surface:
/// - `…/ai-gateway/openai/v1`    → OpenAI-compatible chat completions (via `DatabricksAdapter`)
/// - `…/ai-gateway/anthropic/v1` → Anthropic Messages API (via `AnthropicAdapter`)
/// - bare workspace host / `…/serving-endpoints` → Foundation Model APIs (via `DatabricksAdapter`)
///
/// AI Gateway requests to a registered provider service must carry the
/// `Databricks-Model-Provider-Service` header naming the three-part service
/// (e.g. `workspace.default.openai`), with the raw provider model as the `model` value.
/// Verified live against a workspace, 2026-07.
enum DatabricksGateway {
    static let modelProviderServiceHeader = "Databricks-Model-Provider-Service"

    static func isGateway(_ baseURL: String?) -> Bool {
        normalized(baseURL).contains("/ai-gateway/")
    }

    static func isOpenAIGateway(_ baseURL: String?) -> Bool {
        normalized(baseURL).contains("/ai-gateway/openai")
    }

    static func isAnthropicGateway(_ baseURL: String?) -> Bool {
        normalized(baseURL).contains("/ai-gateway/anthropic")
    }

    /// The Databricks workspace root (`scheme://host[:port]`) from any Databricks URL — the
    /// user may paste a bare host, a `/serving-endpoints` URL, or an `/ai-gateway/…` URL.
    static func workspaceRoot(from rawURL: String) -> String {
        let raw = rawURL.trimmed
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"

        if let components = URLComponents(string: withScheme), let host = components.host {
            let scheme = components.scheme ?? "https"
            if let port = components.port {
                return "\(scheme)://\(host):\(port)"
            }
            return "\(scheme)://\(host)"
        }

        // Fallback: strip a trailing `/serving-endpoints` path and any trailing slash.
        var trimmed = withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
        if trimmed.lowercased().hasSuffix("/serving-endpoints") {
            trimmed = String(trimmed.dropLast("/serving-endpoints".count))
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// The three-part provider service name for the `Databricks-Model-Provider-Service` header,
    /// derived from the `/ai-gateway/<provider>/…` path segment (default location
    /// `workspace.default`, which is where AI Gateway providers live by default). Returns nil for
    /// non-gateway URLs or the unified `mlflow` surface (which does not accept registered providers).
    static func providerServiceName(from baseURL: String?) -> String? {
        let lower = normalized(baseURL)
        guard let range = lower.range(of: "/ai-gateway/") else { return nil }
        let after = lower[range.upperBound...]
        guard let name = after.split(separator: "/").first.map(String.init),
              !name.isEmpty, name != "mlflow", name != "v1" else {
            return nil
        }
        return "workspace.default.\(name)"
    }

    private static func normalized(_ baseURL: String?) -> String {
        (baseURL ?? "").trimmed.lowercased()
    }

    // MARK: - Curated model lists

    // AI Gateway provider services enforce an allowed-models list that Databricks does not expose
    // to a workspace token (the `/models` routes return the wrong set, and the allowed list only
    // surfaces via a 403). So "Fetch from Provider" offers a curated set of each provider's current
    // common models — the user removes any their gateway doesn't allow. Model IDs are the raw
    // upstream names (verified live: `gpt-5.6-luna`, `gpt-4o-mini`, `claude-sonnet-4-5` all query
    // successfully; `databricks-…`-prefixed system names are rejected by BYOK provider services).

    static func curatedOpenAIModels() -> [ModelInfo] {
        [
            reasoningModel("gpt-5.6-sol", "GPT-5.6 Sol", contextWindow: 400_000),
            reasoningModel("gpt-5.6-terra", "GPT-5.6 Terra", contextWindow: 400_000),
            reasoningModel("gpt-5.6-luna", "GPT-5.6 Luna", contextWindow: 400_000),
            reasoningModel("gpt-5", "GPT-5", contextWindow: 400_000),
            reasoningModel("gpt-5-mini", "GPT-5 mini", contextWindow: 400_000),
            reasoningModel("o3", "o3", contextWindow: 200_000),
            reasoningModel("o4-mini", "o4-mini", contextWindow: 200_000),
            visionChatModel("gpt-4o", "GPT-4o", contextWindow: 128_000),
            visionChatModel("gpt-4o-mini", "GPT-4o mini", contextWindow: 128_000),
        ]
    }

    static func curatedAnthropicModels() -> [ModelInfo] {
        // Reasoning is intentionally omitted: extended thinking is not wired through the gateway
        // Anthropic path yet, so the models are exposed as vision chat models only.
        [
            visionChatModel("claude-opus-4-8", "Claude Opus 4.8", contextWindow: 200_000),
            visionChatModel("claude-sonnet-4-6", "Claude Sonnet 4.6", contextWindow: 200_000),
            visionChatModel("claude-sonnet-4-5", "Claude Sonnet 4.5", contextWindow: 200_000),
            visionChatModel("claude-opus-4-1", "Claude Opus 4.1", contextWindow: 200_000),
            visionChatModel("claude-haiku-4-5", "Claude Haiku 4.5", contextWindow: 200_000),
        ]
    }

    private static func reasoningModel(_ id: String, _ name: String, contextWindow: Int) -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            capabilities: [.streaming, .toolCalling, .vision, .reasoning],
            contextWindow: contextWindow,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        )
    }

    private static func visionChatModel(_ id: String, _ name: String, contextWindow: Int) -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            capabilities: [.streaming, .toolCalling, .vision],
            contextWindow: contextWindow,
            reasoningConfig: nil
        )
    }
}
