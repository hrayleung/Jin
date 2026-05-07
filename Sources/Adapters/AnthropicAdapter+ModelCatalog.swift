import Foundation

extension AnthropicAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        if !supportsModelsEndpoint {
            return await validateAPIKeyViaMinimalMessage(key)
        }

        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/models"),
            headers: anthropicHeaders(apiKey: key)
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        if !supportsModelsEndpoint {
            return (ModelCatalog.orderedRecords[providerConfig.type] ?? []).map { r in
                ModelInfo(
                    id: r.id, name: r.displayName, capabilities: r.capabilities,
                    contextWindow: r.contextWindow, maxOutputTokens: r.maxOutputTokens,
                    reasoningConfig: r.reasoningConfig
                )
            }
        }

        var allModels: [ModelInfo] = []
        var afterID: String?
        var seenIDs: Set<String> = []

        while true {
            var components = URLComponents(string: "\(baseURL)/models")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "100")
            ]
            if let afterID {
                queryItems.append(URLQueryItem(name: "after_id", value: afterID))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw LLMError.invalidRequest(message: "Invalid Anthropic models URL")
            }

            let request = NetworkRequestFactory.makeRequest(
                url: url,
                headers: anthropicHeaders(apiKey: apiKey)
            )

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(AnthropicModelsListResponse.self, from: data)

            for model in response.data {
                guard !seenIDs.contains(model.id) else { continue }
                seenIDs.insert(model.id)
                allModels.append(makeModelInfo(from: model))
            }

            guard response.hasMore == true,
                  let lastID = response.lastID,
                  !lastID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  lastID != afterID else {
                break
            }

            afterID = lastID
        }

        return allModels.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Anthropic-compatible providers (e.g. MiniMax Coding Plan) may not expose a `/models` endpoint.
    private var supportsModelsEndpoint: Bool {
        providerConfig.type == .anthropic
    }

    /// Validate by sending a tiny message request and checking for auth errors.
    private func validateAPIKeyViaMinimalMessage(_ key: String) async -> Bool {
        let modelID = providerConfig.models.first?.id
            ?? ModelCatalog.seededModels(for: providerConfig.type).first?.id
            ?? "MiniMax-M2.7"

        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        do {
            let request = try NetworkRequestFactory.makeJSONRequest(
                url: validatedURL("\(baseURL)/messages"),
                headers: anthropicHeaders(apiKey: key),
                body: body
            )
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            let errorMessage = "\(error)".lowercased()
            if errorMessage.contains("401") || errorMessage.contains("403")
                || errorMessage.contains("authentication") || errorMessage.contains("unauthorized")
                || (errorMessage.contains("invalid") && errorMessage.contains("key")) {
                return false
            }
            // Non-auth errors (e.g. 400 bad request) still confirm the key is reachable.
            return true
        }
    }

    private func makeModelInfo(from model: AnthropicModelsListResponse.AnthropicModelInfo) -> ModelInfo {
        ModelCatalog.modelInfo(for: model.id, provider: .anthropic, name: model.displayName)
    }
}
