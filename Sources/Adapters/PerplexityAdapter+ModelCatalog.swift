import Foundation

extension PerplexityAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: key,
            body: Self.validationBody,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        if !providerConfig.models.isEmpty {
            return providerConfig.models
        }

        return Self.defaultModels
    }

    private static let validationBody: [String: Any] = [
        "model": "sonar",
        "messages": [["role": "user", "content": "ping"]],
        "max_tokens": 1,
        "stream": false
    ]

    private static let defaultModels: [ModelInfo] = [
        ModelInfo(
            id: "sonar",
            name: "Sonar",
            capabilities: [.streaming, .vision],
            contextWindow: 128_000,
            reasoningConfig: nil
        ),
        ModelInfo(
            id: "sonar-pro",
            name: "Sonar Pro",
            capabilities: [.streaming, .toolCalling, .vision],
            contextWindow: 200_000,
            reasoningConfig: nil
        ),
        ModelInfo(
            id: "sonar-reasoning-pro",
            name: "Sonar Reasoning Pro",
            capabilities: [.streaming, .toolCalling, .vision, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        ),
        ModelInfo(
            id: "sonar-deep-research",
            name: "Sonar Deep Research",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        )
    ]
}
