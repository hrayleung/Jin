import Foundation

extension BasetenAdapter {
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

        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { remote in
                ModelCatalog.modelInfo(for: remote.id, provider: .baseten, name: remote.id)
            }
        }

        throw LLMError.decodingError(message: "Baseten /models response could not be decoded.")
    }
}
