import Foundation

extension OpenCodeGoAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let modelID = providerConfig.models.first?.id
            ?? ModelCatalog.seededModels(for: .opencodeGo).first?.id
            ?? "glm-5"

        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        do {
            let request: URLRequest
            if Self.isAnthropicModel(modelID) {
                request = try NetworkRequestFactory.makeJSONRequest(
                    url: validatedURL("\(Self.hardcodedBaseURL)/messages"),
                    headers: [
                        "x-api-key": key,
                        "anthropic-version": "2023-06-01"
                    ],
                    body: body
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
