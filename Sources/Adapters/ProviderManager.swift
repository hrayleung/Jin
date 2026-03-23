import Foundation

actor ProviderManager {
    private let networkManager: NetworkManager

    private enum ResolvedCredentials {
        case apiKey(String)
        case noAPIKeyRequired
        case serviceAccount(ServiceAccountCredentials)

        var validationAPIKey: String {
            switch self {
            case .apiKey(let apiKey):
                return apiKey
            case .noAPIKeyRequired, .serviceAccount:
                return ""
            }
        }
    }

    init(
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.networkManager = networkManager
    }

    func createAdapter(for config: ProviderConfig) async throws -> any LLMProviderAdapter {
        let credentials = try await resolveCredentials(for: config)
        return createAdapter(for: config, credentials: credentials)
    }

    private func createAdapter(
        for config: ProviderConfig,
        credentials: ResolvedCredentials
    ) -> any LLMProviderAdapter {
        switch config.type {
        case .openai:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return OpenAIAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .openaiWebSocket:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return OpenAIWebSocketAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .codexAppServer:
            let apiKey = optionalAPIKey(from: credentials)
            return CodexAppServerAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .groq, .mistral, .deepinfra,
             .zhipuCodingPlan, .minimax:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return OpenAICompatibleAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .openrouter:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return OpenRouterAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .anthropic, .minimaxCodingPlan:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return AnthropicAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .perplexity:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return PerplexityAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .cohere:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return CohereAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .together:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return TogetherAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .xai:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return XAIAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .deepseek:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return DeepSeekAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .fireworks:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return FireworksAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .cerebras:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return CerebrasAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .sambanova:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return SambaNovaAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .morphllm:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return MorphLLMAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .opencodeGo:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return OpenCodeGoAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .gemini:
            let apiKey = requiredAPIKey(from: credentials, for: config.type)
            return GeminiAdapter(providerConfig: config, apiKey: apiKey, networkManager: networkManager)
        case .vertexai:
            let serviceAccount = requiredServiceAccount(from: credentials)
            return VertexAIAdapter(
                providerConfig: config,
                serviceAccountJSON: serviceAccount,
                networkManager: networkManager
            )
        }
    }

    func validateConfiguration(for config: ProviderConfig) async throws -> Bool {
        let credentials = try await resolveCredentials(for: config)
        let adapter = createAdapter(for: config, credentials: credentials)
        return try await adapter.validateAPIKey(credentials.validationAPIKey)
    }

    private func resolveCredentials(for config: ProviderConfig) async throws -> ResolvedCredentials {
        if config.type == .vertexai {
            return .serviceAccount(try await resolveServiceAccountCredentials(for: config))
        }

        if config.type == .codexAppServer {
            return try await resolveCodexCredentials(for: config)
        }

        return .apiKey(try await resolveRequiredAPIKey(for: config))
    }

    private func resolveRequiredAPIKey(for config: ProviderConfig) async throws -> String {
        let direct = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        throw ProviderError.missingAPIKey(provider: config.name)
    }

    private func resolveCodexCredentials(for config: ProviderConfig) async throws -> ResolvedCredentials {
        let direct = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty {
            return .apiKey(direct)
        }

        if config.authModeHint == CodexLocalAuthStore.authModeHint {
            if let localKey = CodexLocalAuthStore.loadAPIKey() {
                return .apiKey(localKey)
            }
            throw ProviderError.missingAPIKey(provider: config.name)
        }

        return .noAPIKeyRequired
    }

    private func resolveServiceAccountCredentials(for config: ProviderConfig) async throws -> ServiceAccountCredentials {
        let direct = (config.serviceAccountJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !direct.isEmpty else {
            throw ProviderError.missingServiceAccount(provider: config.name)
        }

        do {
            return try JSONDecoder().decode(
                ServiceAccountCredentials.self,
                from: Data(direct.utf8)
            )
        } catch {
            throw ProviderError.invalidServiceAccount
        }
    }

    private func requiredAPIKey(from credentials: ResolvedCredentials, for providerType: ProviderType) -> String {
        guard case .apiKey(let apiKey) = credentials else {
            fatalError("Expected API key credentials for provider type: \(providerType.rawValue)")
        }
        return apiKey
    }

    private func optionalAPIKey(from credentials: ResolvedCredentials) -> String {
        switch credentials {
        case .apiKey(let apiKey):
            return apiKey
        case .noAPIKeyRequired:
            return ""
        case .serviceAccount:
            fatalError("Unexpected service account credentials for Codex App Server")
        }
    }

    private func requiredServiceAccount(from credentials: ResolvedCredentials) -> ServiceAccountCredentials {
        guard case .serviceAccount(let serviceAccount) = credentials else {
            fatalError("Expected service account credentials for Vertex AI")
        }
        return serviceAccount
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
