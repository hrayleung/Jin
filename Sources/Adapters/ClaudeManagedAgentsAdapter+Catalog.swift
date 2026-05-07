import Foundation

extension ClaudeManagedAgentsAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = NetworkRequestFactory.makeRequest(
            url: try managedAgentsBetaURL("/v1/agents"),
            method: "GET",
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
        let adapter = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: providerConfig.id,
                name: providerConfig.name,
                type: .anthropic,
                iconID: providerConfig.iconID,
                authModeHint: providerConfig.authModeHint,
                apiKey: providerConfig.apiKey,
                serviceAccountJSON: providerConfig.serviceAccountJSON,
                baseURL: "\(baseURL)/v1",
                models: providerConfig.models,
                isEnabled: providerConfig.isEnabled
            ),
            apiKey: apiKey,
            networkManager: networkManager
        )
        return try await adapter.fetchAvailableModels()
    }

    func listAgents() async throws -> [ClaudeManagedAgentDescriptor] {
        let object = try await fetchManagedAgentsCollection(path: "/v1/agents")
        return ClaudeManagedAgentCatalogSupport.agentDescriptors(from: object)
    }

    func listEnvironments() async throws -> [ClaudeManagedEnvironmentDescriptor] {
        let object = try await fetchManagedAgentsCollection(path: "/v1/environments")
        return ClaudeManagedAgentCatalogSupport.environmentDescriptors(from: object)
    }

    var baseURL: String {
        providerConfig.baseURL ?? "https://api.anthropic.com"
    }

    func anthropicHeaders(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": Self.managedAgentsBeta
        ]
    }

    func managedAgentsBetaURL(_ path: String) throws -> URL {
        try validatedURL("\(baseURL)\(path)?beta=true")
    }

    private static let managedAgentsBeta = "managed-agents-2026-04-01"

    private func fetchManagedAgentsCollection(path: String) async throws -> [String: JSONValue] {
        let request = NetworkRequestFactory.makeRequest(
            url: try managedAgentsBetaURL(path),
            method: "GET",
            headers: anthropicHeaders(apiKey: apiKey)
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try ClaudeManagedAgentCatalogSupport.collectionObject(from: data)
    }
}
