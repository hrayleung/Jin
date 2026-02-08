import Foundation

actor ProviderManager {
    private let networkManager: NetworkManager

    init(
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.networkManager = networkManager
    }

    func createAdapter(for config: ProviderConfig) async throws -> any LLMProviderAdapter {
        switch config.type {
        case .openai:
            let apiKey = try await resolveAPIKey(for: config)
            return OpenAIAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .openaiCompatible:
            let apiKey = try await resolveAPIKey(for: config)
            return OpenAICompatibleAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .openrouter:
            let apiKey = try await resolveAPIKey(for: config)
            return OpenRouterAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .anthropic:
            let apiKey = try await resolveAPIKey(for: config)
            return AnthropicAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .xai:
            let apiKey = try await resolveAPIKey(for: config)
            return XAIAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .deepseek:
            let apiKey = try await resolveAPIKey(for: config)
            return DeepSeekAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .fireworks:
            let apiKey = try await resolveAPIKey(for: config)
            return FireworksAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .cerebras:
            let apiKey = try await resolveAPIKey(for: config)
            return CerebrasAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .gemini:
            let apiKey = try await resolveAPIKey(for: config)
            return GeminiAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .vertexai:
            let credentials: ServiceAccountCredentials
            do {
                let jsonString = try await resolveServiceAccountJSON(for: config)
                credentials = try JSONDecoder().decode(
                    ServiceAccountCredentials.self,
                    from: Data(jsonString.utf8)
                )
            } catch {
                throw ProviderError.invalidServiceAccount
            }
            return VertexAIAdapter(
                providerConfig: config,
                serviceAccountJSON: credentials,
                networkManager: networkManager
            )
        }
    }

    func validateConfiguration(for config: ProviderConfig) async throws -> Bool {
        let adapter = try await createAdapter(for: config)

        switch config.type {
        case .openai, .openaiCompatible, .openrouter, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            let apiKey = try await resolveAPIKey(for: config)
            return try await adapter.validateAPIKey(apiKey)

        case .vertexai:
            return try await adapter.validateAPIKey("")
        }
    }

    private func resolveAPIKey(for config: ProviderConfig) async throws -> String {
        let direct = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        throw ProviderError.missingAPIKey(provider: config.name)
    }

    private func resolveServiceAccountJSON(for config: ProviderConfig) async throws -> String {
        let direct = (config.serviceAccountJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        throw ProviderError.missingServiceAccount(provider: config.name)
    }
}

enum ProviderError: Error, LocalizedError {
    case missingAPIKey(provider: String)
    case missingServiceAccount(provider: String)
    case invalidServiceAccount
    case adapterNotFound(providerType: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "API key not found for \(provider). Please configure it in Settings."
        case .missingServiceAccount(let provider):
            return "Service account JSON not found for \(provider). Please configure it in Settings."
        case .invalidServiceAccount:
            return "Invalid service account JSON format."
        case .adapterNotFound(let providerType):
            return "No adapter found for provider type: \(providerType)"
        }
    }
}
