import Foundation

actor ProviderManager {
    private let networkManager: NetworkManager

    init(
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.networkManager = networkManager
    }

    func createAdapter(for config: ProviderConfig) async throws -> any LLMProviderAdapter {
        if config.type == .vertexai {
            return try await createVertexAIAdapter(for: config)
        }

        let apiKey = try await resolveAPIKey(for: config)
        return createAPIKeyAdapter(for: config, apiKey: apiKey)
    }

    private func createVertexAIAdapter(for config: ProviderConfig) async throws -> any LLMProviderAdapter {
        let jsonString: String
        let credentials: ServiceAccountCredentials
        do {
            jsonString = try await resolveServiceAccountJSON(for: config)
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

    private func createAPIKeyAdapter(for config: ProviderConfig, apiKey: String) -> any LLMProviderAdapter {
        switch config.type {
        case .openai:
            return OpenAIAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .codexAppServer:
            return CodexAppServerAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .openaiCompatible, .groq, .mistral, .deepinfra:
            return OpenAICompatibleAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .openrouter:
            return OpenRouterAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .anthropic:
            return AnthropicAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .perplexity:
            return PerplexityAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .cohere:
            return CohereAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .xai:
            return XAIAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .deepseek:
            return DeepSeekAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .fireworks:
            return FireworksAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .cerebras:
            return CerebrasAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .gemini:
            return GeminiAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .vertexai:
            fatalError("VertexAI should be handled by createVertexAIAdapter")
        }
    }

    func validateConfiguration(for config: ProviderConfig) async throws -> Bool {
        let adapter = try await createAdapter(for: config)
        let apiKey = (config.type == .vertexai) ? "" : try await resolveAPIKey(for: config)
        return try await adapter.validateAPIKey(apiKey)
    }

    private func resolveAPIKey(for config: ProviderConfig) async throws -> String {
        let direct = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        if config.type == .codexAppServer {
            if config.authModeHint == CodexLocalAuthStore.authModeHint {
                if let localKey = CodexLocalAuthStore.loadAPIKey() {
                    return localKey
                }
                throw ProviderError.missingAPIKey(provider: config.name)
            }
            return ""
        }

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
