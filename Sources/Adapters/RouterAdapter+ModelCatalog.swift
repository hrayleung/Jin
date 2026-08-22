import Foundation

extension RouterAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    /// Router's `/v1/models` is unusually rich: alongside the OpenAI `id`/`object`
    /// envelope every entry carries a `router` object with exact limits, input
    /// modalities, tool/reasoning support and the model's effort band. Reading it
    /// beats trusting the bundled snapshot, because a key only ever sees the models
    /// it is authorized for and Router relabels models as upstreams change.
    func fetchAvailableModels() async throws -> [ModelInfo] {
        do {
            let request = makeGETRequest(
                url: try validatedURL("\(baseURL)/models"),
                apiKey: apiKey,
                includeUserAgent: false
            )
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder.snakeCaseConverting()
                .decode(RouterModelsListResponse.self, from: data)
            let live = response.data.map(Self.modelInfo(from:))
            if !live.isEmpty { return live }
            return Self.bundledCatalogModels()
        } catch {
            // Never leave the picker empty: a transient failure should fall back to the
            // bundled snapshot rather than blanking a provider the user just configured.
            return Self.bundledCatalogModels()
        }
    }

    // MARK: - Mapping

    private static func modelInfo(from model: RouterModelsListResponse.ModelData) -> ModelInfo {
        let bundled = ModelCatalog.entry(for: model.id, provider: .router)
        let router = model.router
        let capabilities = router?.capabilities

        var resolved: ModelCapability = [.streaming]
        if capabilities?.tools?.supported == true { resolved.insert(.toolCalling) }
        if capabilities?.modalities?.input?.contains("image") == true { resolved.insert(.vision) }
        if capabilities?.modalities?.input?.contains("audio") == true { resolved.insert(.audio) }
        if capabilities?.reasoning?.supported == true { resolved.insert(.reasoning) }
        // A model Router doesn't describe falls back to whatever the snapshot knew.
        if capabilities == nil, let bundled { resolved = bundled.capabilities }

        let contextWindow = router?.limits?.contextWindow.flatMap { $0 > 0 ? $0 : nil }
            ?? bundled?.contextWindow
        let maxOutputTokens = router?.limits?.maxOutputTokens.flatMap { $0 > 0 ? $0 : nil }
            ?? bundled?.maxOutputTokens

        return ModelInfo(
            id: model.id,
            name: router?.displayName ?? model.displayName ?? bundled?.displayName ?? model.id,
            capabilities: resolved,
            contextWindow: contextWindow ?? 128_000,
            maxOutputTokens: maxOutputTokens,
            reasoningConfig: resolvedReasoningConfig(for: model, bundled: bundled)
        )
    }

    private static func resolvedReasoningConfig(
        for model: RouterModelsListResponse.ModelData,
        bundled: ModelCatalogEntry?
    ) -> ModelReasoningConfig? {
        guard let reasoning = model.router?.capabilities?.reasoning else {
            return bundled?.reasoningConfig
        }
        // `supported: true` with an EMPTY efforts array means the model always reasons
        // and rejects every effort value ("400 Invalid reasoning effort."). Return nil
        // so nothing ever puts `reasoning.effort` on the wire for it.
        guard reasoning.supported == true,
              let efforts = reasoning.efforts,
              !efforts.isEmpty
        else { return nil }

        let defaultEffort = reasoning.defaultEffort.flatMap(ReasoningEffort.init(rawValue:))
        return ModelReasoningConfig(type: .effort, defaultEffort: defaultEffort)
    }

    private static func bundledCatalogModels() -> [ModelInfo] {
        (ModelCatalog.orderedRecords[.router] ?? []).map { record in
            ModelInfo(
                id: record.id,
                name: record.displayName,
                capabilities: record.capabilities,
                contextWindow: record.contextWindow,
                maxOutputTokens: record.maxOutputTokens,
                reasoningConfig: record.reasoningConfig
            )
        }
    }
}

// MARK: - Wire types

/// `GET https://api.router.com/v1/models`. Decoded with a snake-case-converting
/// decoder; every field below `data[].router` is optional because Router versions the
/// object (`schema_version`) and a future shape must degrade to the snapshot rather
/// than failing the whole fetch.
private struct RouterModelsListResponse: Decodable {
    let data: [ModelData]

    struct ModelData: Decodable {
        let id: String
        let displayName: String?
        let ownedBy: String?
        let router: RouterMetadata?
    }

    struct RouterMetadata: Decodable {
        let displayName: String?
        let providerDisplayName: String?
        let status: String?
        let limits: Limits?
        let capabilities: Capabilities?
    }

    struct Limits: Decodable {
        let contextWindow: Int?
        let maxInputTokens: Int?
        let maxOutputTokens: Int?
    }

    struct Capabilities: Decodable {
        let modalities: Modalities?
        let tools: Tools?
        let structuredOutputs: Bool?
        let temperature: Bool?
        let promptCaching: Bool?
        let reasoning: Reasoning?
    }

    struct Modalities: Decodable {
        let input: [String]?
        let output: [String]?
    }

    struct Tools: Decodable {
        let supported: Bool?
    }

    struct Reasoning: Decodable {
        let supported: Bool?
        let efforts: [Effort]?
        let defaultEffort: String?

        struct Effort: Decodable {
            let value: String
        }
    }
}
