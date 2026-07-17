import Foundation

extension DatabricksAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        // The serving-endpoints listing API is the reachability + token-scope check for the
        // workspace. AI Gateway provider services are serving-backed, so this also confirms a
        // gateway token has the required `model-serving` scope.
        await validateAPIKeyViaGET(
            url: try validatedURL(servingEndpointsListURLString),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        if isOpenAIGateway {
            // AI Gateway native surfaces don't expose the provider service's allowed-models list,
            // so offer a curated set of current OpenAI models — remove any this gateway rejects.
            return DatabricksGateway.curatedOpenAIModels()
        }
        return try await fetchServingEndpointModels()
    }

    /// Foundation Model APIs: list serving endpoints and keep the chat-task ones.
    private func fetchServingEndpointModels() async throws -> [ModelInfo] {
        let url = try validatedURL(servingEndpointsListURLString)
        let request = makeGETRequest(url: url, apiKey: apiKey)
        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DatabricksServingEndpointsResponse.self, from: data)

        return (response.endpoints ?? [])
            .filter { $0.isChatEndpoint }
            .map { endpoint in
                makeModelInfo(id: endpoint.name, displayName: endpoint.foundationModelDisplayName)
            }
    }

    /// Whether the given serving-endpoint name supports image input. Prefers the configured /
    /// catalog capability, then falls back to a conservative family heuristic for endpoints
    /// discovered dynamically that are not in the catalog.
    func modelSupportsVision(_ modelID: String) -> Bool {
        if let configured = findConfiguredModel(in: providerConfig, for: modelID) {
            return configured.capabilities.contains(.vision)
        }
        if let entry = ModelCatalog.entry(for: modelID, provider: .databricks) {
            return entry.capabilities.contains(.vision)
        }
        return DatabricksModelHeuristics.supportsVision(modelID)
    }

    private func makeModelInfo(id: String, displayName: String?) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .databricks) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .databricks, name: displayName)
        }

        var fallback = DatabricksFallbackModelInfo(id: id, displayName: displayName)
        fallback.applyCapabilityHeuristics()
        return fallback.modelInfo
    }
}

// MARK: - Serving Endpoints Listing Response

/// Response shape of `GET /api/2.0/serving-endpoints`.
struct DatabricksServingEndpointsResponse: Decodable {
    let endpoints: [Endpoint]?

    struct Endpoint: Decodable {
        let name: String
        let task: String?
        let config: Config?

        /// Chat endpoints report `task == "llm/v1/chat"`. Completions and embeddings carry
        /// their own `llm/v1/*` task and are excluded; task-less endpoints (custom pyfunc
        /// deployments, feature serving, etc.) are not OpenAI-chat-compatible and are excluded
        /// too. A user with a bespoke chat endpoint that lacks a task can still add its ID by
        /// hand in the model picker.
        var isChatEndpoint: Bool {
            task?.trimmedLowercased == "llm/v1/chat"
        }

        var foundationModelDisplayName: String? {
            config?.servedEntities?.compactMap { $0.foundationModel?.displayName?.trimmedNonEmpty }.first
        }

        struct Config: Decodable {
            let servedEntities: [ServedEntity]?

            struct ServedEntity: Decodable {
                let foundationModel: FoundationModel?

                struct FoundationModel: Decodable {
                    let displayName: String?
                    let name: String?
                }
            }
        }
    }
}

// MARK: - Fallback Heuristics

/// Conservative capability heuristics for serving endpoints discovered dynamically that are
/// not in the seeded catalog. Databricks proxies many model families under `databricks-*`
/// endpoint names, so family detection drives vision/reasoning defaults.
enum DatabricksModelHeuristics {
    static func supportsVision(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("gpt-oss") { return false }
        if lower.contains("embedding") || lower.contains("-embed") { return false }
        return lower.contains("claude")
            || (lower.contains("gemini") && !lower.contains("embedding"))
            // Gemma multimodal variants only: Gemma 3 (4B/12B/27B) and Gemma 4 have vision;
            // Gemma 1, Gemma 2 (all sizes) and Gemma 3 1B are text-only.
            || (lower.contains("gemma-3") && !lower.contains("gemma-3-1b"))
            || lower.contains("gemma-4")
            || lower.contains("llama-4") || lower.contains("maverick") || lower.contains("scout")
            || lower.contains("gpt-5")
            || lower.contains("pixtral")
    }

    static func supportsReasoning(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("embedding") || lower.contains("-embed") { return false }
        // Claude Haiku is non-reasoning across generations.
        if lower.contains("haiku") { return false }
        if lower.contains("claude") {
            // Extended thinking exists on Claude 3.7 and 4.x/5.x; Claude 2.x, instant, 3.0
            // and 3.5 do not reason.
            if lower.contains("claude-2") || lower.contains("claude-instant")
                || lower.contains("claude-3-opus") || lower.contains("claude-3-sonnet")
                || lower.contains("claude-3-5") || lower.contains("claude-3.5") {
                return false
            }
            return true
        }
        if lower.contains("qwen3") || lower.contains("qwen35") {
            // Non-thinking `-instruct` variants don't reason; explicit thinking variants are
            // caught by the keyword check below.
            return !lower.contains("instruct")
        }
        return lower.contains("gpt-oss")
            || lower.contains("gpt-5")
            || lower.contains("gemini-3")
            || lower.contains("gemini-2-5") || lower.contains("gemini-2.5")
            || lower.contains("deepseek-r1")
            || lower.contains("reasoning") || lower.contains("thinking")
    }
}

private struct DatabricksFallbackModelInfo {
    let id: String
    let displayName: String?
    private let lowerID: String
    private var capabilities: ModelCapability = [.streaming, .toolCalling]
    private var contextWindow = 128_000
    private var reasoningConfig: ModelReasoningConfig?

    init(id: String, displayName: String?) {
        self.id = id
        self.displayName = displayName
        self.lowerID = id.lowercased()
    }

    var modelInfo: ModelInfo {
        ModelInfo(
            id: id,
            name: displayName?.trimmedNonEmpty ?? id,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    mutating func applyCapabilityHeuristics() {
        if DatabricksModelHeuristics.supportsVision(id) {
            capabilities.insert(.vision)
        }
        if DatabricksModelHeuristics.supportsReasoning(id) {
            capabilities.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        }

        // Widen context for known large-context families.
        if lowerID.contains("gemini") || lowerID.contains("gpt-5") {
            contextWindow = 1_000_000
        } else if lowerID.contains("qwen") {
            contextWindow = 256_000
        }
    }
}
