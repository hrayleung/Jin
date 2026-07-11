import Foundation

extension MetaAdapter {
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
        let list = try JSONDecoder().decode(MetaModelList.self, from: data)
        return list.data.map { $0.modelInfo() }
    }
}

private struct MetaModelList: Decodable {
    let data: [MetaModelEntry]
}

private struct MetaModelEntry: Decodable {
    let id: String

    func modelInfo() -> ModelInfo {
        if let catalogEntry = ModelCatalog.entry(for: id, provider: .meta) {
            return ModelInfo(
                id: id,
                name: catalogEntry.displayName,
                capabilities: catalogEntry.capabilities,
                contextWindow: catalogEntry.contextWindow,
                maxOutputTokens: catalogEntry.maxOutputTokens,
                reasoningConfig: catalogEntry.reasoningConfig
            )
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            maxOutputTokens: nil,
            reasoningConfig: nil
        )
    }
}
