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

    /// Whether the given serving-endpoint name supports image input, from its configured or
    /// cataloged capabilities. Uncataloged endpoints are treated conservatively (no vision)
    /// rather than guessing from the name.
    func modelSupportsVision(_ modelID: String) -> Bool {
        if let configured = findConfiguredModel(in: providerConfig, for: modelID) {
            return configured.capabilities.contains(.vision)
        }
        return ModelCatalog.entry(for: modelID, provider: .databricks)?
            .capabilities.contains(.vision) ?? false
    }

    private func makeModelInfo(id: String, displayName: String?) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .databricks) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .databricks, name: displayName)
        }

        // Uncataloged serving endpoint: keep capabilities conservative rather than inferring from
        // the name. Vision/reasoning stay off and the context window uses a safe default until the
        // exact model is added to `ModelCatalogRecords+Databricks.swift` with verified capabilities.
        // TODO: catalog additional Databricks-hosted models as they are verified.
        return ModelInfo(
            id: id,
            name: displayName?.trimmedNonEmpty ?? id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil
        )
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

