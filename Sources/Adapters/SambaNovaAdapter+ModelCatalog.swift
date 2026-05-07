import Foundation

extension SambaNovaAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURLRoot)/v1/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(url: try validatedURL("\(baseURLRoot)/v1/models"), apiKey: apiKey)
        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func modelSupportsVision(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.contains("minimax-m2.5")
            || lower.contains("maverick")
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .sambanova) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .sambanova)
        }

        var fallback = SambaNovaFallbackModelInfo(id: id)
        fallback.applyCapabilityHeuristics()
        fallback.applyContextWindowHeuristics()
        return fallback.modelInfo
    }
}

private struct SambaNovaFallbackModelInfo {
    let id: String
    private let lowerID: String
    private var capabilities: ModelCapability = [.streaming, .toolCalling]
    private var contextWindow = 128_000
    private var reasoningConfig: ModelReasoningConfig?

    init(id: String) {
        self.id = id
        self.lowerID = id.lowercased()
    }

    var modelInfo: ModelInfo {
        ModelInfo(
            id: id,
            name: id,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    mutating func applyCapabilityHeuristics() {
        if lowerID.contains("deepseek-r1") {
            capabilities = [.streaming, .toolCalling, .reasoning]
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lowerID.contains("deepseek-v3.1") {
            capabilities.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lowerID.contains("qwen3") {
            capabilities.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lowerID == "gpt-oss-120b" {
            capabilities.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        } else if lowerID.contains("minimax-m2.5") {
            capabilities.insert(.vision)
            contextWindow = 160_000
        } else if lowerID.contains("maverick") {
            capabilities.insert(.vision)
        }
    }

    mutating func applyContextWindowHeuristics() {
        if lowerID.contains("8b-instruct") {
            contextWindow = 16_000
        } else if lowerID.contains("qwen3-32b") {
            contextWindow = 32_000
        } else if lowerID.contains("qwen3-235b") {
            contextWindow = 64_000
        } else if lowerID.contains("deepseek-v3.2") {
            contextWindow = 8_192
        }
    }
}
