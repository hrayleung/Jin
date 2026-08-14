import Foundation

extension OpenCodeGoAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let modelID = providerConfig.models.first?.id
            ?? ModelCatalog.seededModels(for: .opencodeGo).first?.id
            ?? "glm-5.3"

        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        do {
            let request: URLRequest
            if Self.usesAnthropicMessagesEndpoint(modelID) {
                request = try NetworkRequestFactory.makeJSONRequest(
                    url: validatedURL("\(Self.hardcodedBaseURL)/messages"),
                    headers: [
                        "x-api-key": key,
                        "anthropic-version": "2023-06-01"
                    ],
                    body: body
                )
            } else if Self.usesOpenAIResponsesEndpoint(modelID) {
                // Responses-route models (gpt-5.6-luna) are not served on /chat/completions,
                // so validate on the endpoint they actually use. `input` accepts a bare
                // string, and `max_output_tokens` has a documented minimum of 16.
                request = try makeAuthorizedJSONRequest(
                    url: validatedURL("\(Self.hardcodedBaseURL)/responses"),
                    apiKey: key,
                    body: [
                        "model": modelID,
                        "input": "hi",
                        "max_output_tokens": 16,
                        "stream": false
                    ]
                )
            } else {
                request = try makeAuthorizedJSONRequest(
                    url: validatedURL("\(Self.hardcodedBaseURL)/chat/completions"),
                    apiKey: key,
                    body: body
                )
            }
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            let errorMessage = "\(error)".lowercased()
            if errorMessage.contains("401") || errorMessage.contains("403")
                || errorMessage.contains("authentication") || errorMessage.contains("unauthorized")
                || (errorMessage.contains("invalid") && errorMessage.contains("key")) {
                return false
            }
            return true
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        do {
            let request = makeGETRequest(
                url: try validatedURL("\(Self.hardcodedBaseURL)/models"),
                apiKey: apiKey,
                includeUserAgent: false
            )
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let live = response.data.map {
                OpenAICompatibleModelMappingSupport.modelInfo(from: $0, providerType: .opencodeGo)
            }
            if !live.isEmpty { return live }
            return bundledCatalogModels()
        } catch {
            // OpenCode Go's `/models` is normally a public HTTP 200, but fall back to the
            // bundled catalog if the request or decode fails so the picker is never empty.
            return bundledCatalogModels()
        }
    }

    private func bundledCatalogModels() -> [ModelInfo] {
        (ModelCatalog.orderedRecords[.opencodeGo] ?? []).map { record in
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
