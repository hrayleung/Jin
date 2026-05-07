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
        let request = makeGETRequest(url: try validatedURL("\(baseURLRoot)/v1/models"), apiKey: apiKey)
        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
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
