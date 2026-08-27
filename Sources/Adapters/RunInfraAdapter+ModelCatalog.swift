import Foundation

extension RunInfraAdapter {
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

        if let runinfraModels = try? decoder.decode(RunInfraModelsResponse.self, from: data) {
            return runinfraModels.data.map(makeModelInfo(from:))
        }

        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { makeModelInfo(id: $0.id, liveContextWindow: $0.contextWindow, liveMaxOutputTokens: nil) }
        }

        throw LLMError.decodingError(message: "RunInfra /models response could not be decoded.")
    }

    private func makeModelInfo(from model: RunInfraModelsResponse.Model) -> ModelInfo {
        makeModelInfo(
            id: model.id,
            liveContextWindow: model.contextWindow ?? model.contextLength,
            liveMaxOutputTokens: model.maxOutputTokens
        )
    }

    private func makeModelInfo(id: String, liveContextWindow: Int?, liveMaxOutputTokens: Int?) -> ModelInfo {
        if let entry = ModelCatalog.entry(for: id, provider: .runinfra) {
            let contextWindow = normalizedPositiveInt(liveContextWindow) ?? entry.contextWindow
            return ModelInfo(
                id: id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: normalizedPositiveInt(liveContextWindow) ?? 128_000,
            maxOutputTokens: normalizedPositiveInt(liveMaxOutputTokens),
            reasoningConfig: nil
        )
    }

    private func normalizedPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

/// RunInfra `GET /v1/models` adds gateway limit fields on top of the OpenAI Model object.
private struct RunInfraModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let contextWindow: Int?
        let contextLength: Int?
        let maxOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case contextWindow = "context_window"
            case contextLength = "context_length"
            case maxOutputTokens = "max_output_tokens"
        }
    }
}
