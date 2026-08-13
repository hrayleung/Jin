import Foundation

extension ModalAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let normalized = ModalProxyToken.normalized(key)
        let headers = ModalAdapter.authHeaders(for: normalized)
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: normalized,
            authHeader: headers.auth,
            additionalHeaders: headers.additional,
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
        let headers = ModalAdapter.authHeaders(for: apiKey)
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            authHeader: headers.auth,
            additionalHeaders: headers.additional,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()

        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { remote in
                let info = ModelCatalog.modelInfo(
                    for: remote.id,
                    provider: .modal,
                    name: ModalEndpointSupport.displayName(forModelID: remote.id)
                )
                return ModalEndpointSupport.applyEndpointMetadataIfNeeded(to: info)
            }
        }

        throw LLMError.decodingError(message: "Modal /models response could not be decoded.")
    }

    /// The shared gateway routes on the `model` field, so an Auto Endpoint shows up
    /// as its own hostname (`my-endpoint.us-west.modal.direct`); show just the
    /// endpoint name in the picker.
    ///
    /// Returns nil for anything else so the catalog's own display name wins —
    /// passing a name here overrides it, which would render a Shared API model as
    /// its raw repo ID instead of "Kimi K3".
    static func endpointDisplayName(forModelID modelID: String) -> String? {
        ModalEndpointSupport.displayName(forModelID: modelID)
    }
}
