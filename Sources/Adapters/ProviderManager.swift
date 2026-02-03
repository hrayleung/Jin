import Foundation

actor ProviderManager {
    private let networkManager: NetworkManager
    private let keychainManager: KeychainManager

    init(
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.networkManager = networkManager
        keychainManager = KeychainManager()
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
        case .openai, .anthropic, .xai:
            let apiKey = try await resolveAPIKey(for: config)
            return try await adapter.validateAPIKey(apiKey)

        case .vertexai:
            return try await adapter.validateAPIKey("")
        }
    }

    private func resolveAPIKey(for config: ProviderConfig) async throws -> String {
        let direct = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        let keychainID = (config.apiKeyKeychainID ?? config.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !keychainID.isEmpty,
           let stored = try await keychainManager.getAPIKey(for: keychainID) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        throw ProviderError.missingAPIKey(provider: config.name)
    }

    private func resolveServiceAccountJSON(for config: ProviderConfig) async throws -> String {
        let direct = (config.serviceAccountJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        let keychainID = (config.apiKeyKeychainID ?? config.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !keychainID.isEmpty,
           let stored = try await keychainManager.getServiceAccountJSON(for: keychainID) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

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
