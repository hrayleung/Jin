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
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw ProviderError.missingAPIKey(provider: config.name)
            }
            return OpenAIAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .anthropic:
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw ProviderError.missingAPIKey(provider: config.name)
            }
            return AnthropicAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .xai:
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw ProviderError.missingAPIKey(provider: config.name)
            }
            return XAIAdapter(
                providerConfig: config,
                apiKey: apiKey,
                networkManager: networkManager
            )

        case .vertexai:
            let jsonString = (config.serviceAccountJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jsonString.isEmpty else {
                throw ProviderError.missingServiceAccount(provider: config.name)
            }
            let credentials: ServiceAccountCredentials
            do {
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
        case .openai, .anthropic, .xai:
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return try await adapter.validateAPIKey(apiKey)

        case .vertexai:
            return try await adapter.validateAPIKey("")
        }
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
