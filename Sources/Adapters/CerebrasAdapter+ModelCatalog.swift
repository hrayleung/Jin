import Foundation

extension CerebrasAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURLRoot)/v1/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        try await fetchOpenAICompatibleModels(
            baseURLRoot: baseURLRoot,
            apiKey: apiKey,
            networkManager: networkManager,
            makeModelInfo: makeModelInfo(id:)
        )
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .cerebras) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .cerebras)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil
        )
    }
}
