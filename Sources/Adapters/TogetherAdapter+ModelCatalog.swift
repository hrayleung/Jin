import Foundation

extension TogetherAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
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
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()

        if let models = try? decoder.decode([TogetherModelInfo].self, from: data) {
            return models.map(makeModelInfo(from:))
        }

        // Compatibility fallback when a proxy returns OpenAI's `data` shape.
        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { makeModelInfo(id: $0.id, displayName: nil) }
        }

        throw LLMError.decodingError(message: "Together /models response could not be decoded.")
    }

    private func makeModelInfo(from model: TogetherModelInfo) -> ModelInfo {
        makeModelInfo(id: model.id, displayName: model.displayName)
    }

    private func makeModelInfo(id: String, displayName: String?) -> ModelInfo {
        ModelCatalog.modelInfo(for: id, provider: .together, name: displayName ?? id)
    }
}

private struct TogetherModelInfo: Decodable {
    let id: String
    let type: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case displayName = "display_name"
    }
}
