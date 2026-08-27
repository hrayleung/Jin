import Foundation

extension MakoraAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = makeGETRequest(
            url: try validatedURL(MakoraModelSupport.modelsListURL(baseURL: baseURL)),
            apiKey: key,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL(MakoraModelSupport.modelsListURL(baseURL: baseURL)),
            apiKey: apiKey,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()

        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { makeModelInfo(id: $0.id) }
        }

        if let models = try? decoder.decode([MakoraListedModel].self, from: data) {
            return models.map { makeModelInfo(id: $0.id) }
        }

        throw LLMError.decodingError(message: "Makora /models response could not be decoded.")
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        let canonical = MakoraModelSupport.canonicalModelID(for: id)
        let catalog = ModelCatalog.modelInfo(for: canonical, provider: .makora)
        return ModelInfo(
            id: id,
            name: catalog.name,
            capabilities: catalog.capabilities,
            contextWindow: catalog.contextWindow,
            maxOutputTokens: catalog.maxOutputTokens,
            reasoningConfig: catalog.reasoningConfig
        )
    }
}

private struct MakoraListedModel: Decodable {
    let id: String
}
