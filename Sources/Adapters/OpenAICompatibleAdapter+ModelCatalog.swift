import Foundation

extension OpenAICompatibleAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        if providerConfig.type == .githubCopilot {
            return try await validateGitHubModelsToken(key)
        }

        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: key,
            authHeader: providerAuthenticationHeader(apiKey: key),
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: apiKey,
            authHeader: providerAuthenticationHeader(apiKey: apiKey),
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        let (data, _) = try await networkManager.sendRequest(request)

        if providerConfig.type == .githubCopilot {
            let response = try JSONDecoder().decode([GitHubModelsCatalogModel].self, from: data)
            return response.compactMap(OpenAICompatibleModelMappingSupport.gitHubModelInfo(from:))
        }

        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        let models = response.data.map {
            OpenAICompatibleModelMappingSupport.modelInfo(from: $0, providerType: providerConfig.type)
        }
        if providerConfig.type == .mimoTokenPlanOpenAI {
            return models.filter { !OpenAICompatibleModelMappingSupport.isMiMoTTSModelID($0.id) }
        }
        return models
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? providerConfig.type.defaultBaseURL ?? "https://api.openai.com/v1").trimmed
        let trimmed = normalizedCloudflareGatewayBaseURL(from: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v1"
        }

        return trimmed
    }

    var modelsListURLString: String {
        if providerConfig.type == .githubCopilot {
            guard let base = URL(string: baseURL), let host = base.host else {
                return "https://models.github.ai/catalog/models"
            }

            var components = URLComponents()
            components.scheme = base.scheme ?? "https"
            components.host = host
            components.port = base.port
            components.path = "/catalog/models"
            return components.url?.absoluteString ?? "https://models.github.ai/catalog/models"
        }

        return "\(baseURL)/models"
    }

    var acceptHeaderValue: String {
        providerConfig.type == .githubCopilot ? "application/vnd.github+json" : "application/json"
    }

    func applyProviderHeaders(to request: inout URLRequest) {
        request.setValue(jinUserAgent, forHTTPHeaderField: "User-Agent")

        guard providerConfig.type == .githubCopilot else { return }
        request.setValue(Self.gitHubModelsAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    func providerAuthenticationHeader(apiKey: String) -> (key: String, value: String)? {
        guard providerConfig.type == .mimoTokenPlanOpenAI else { return nil }
        return (key: "api-key", value: apiKey)
    }

    func applyCloudflareGatewayCacheHeaders(to request: inout URLRequest, controls: GenerationControls) {
        guard providerConfig.type == .cloudflareAIGateway else { return }

        if controls.contextCache?.mode == .off {
            request.setValue("true", forHTTPHeaderField: "cf-aig-skip-cache")
            return
        }

        let ttlSeconds = cloudflareGatewayCacheTTLSeconds(from: controls.contextCache?.ttl)
        request.setValue(String(ttlSeconds), forHTTPHeaderField: "cf-aig-cache-ttl")
    }

    private static let gitHubModelsAPIVersion = "2022-11-28"

    private func normalizedCloudflareGatewayBaseURL(from value: String) -> String {
        guard providerConfig.type == .cloudflareAIGateway else { return value }

        let lower = value.lowercased()
        if lower.hasSuffix("/{provider}") {
            let prefix = value.dropLast("/{provider}".count)
            return "\(prefix)/compat"
        }

        return value
    }

    private func validateGitHubModelsToken(_ key: String) async throws -> Bool {
        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: key,
            authHeader: providerAuthenticationHeader(apiKey: key),
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    private func cloudflareGatewayCacheTTLSeconds(from ttl: ContextCacheTTL?) -> Int {
        switch ttl {
        case .hour1:
            return 3_600
        case .customSeconds(let seconds):
            return max(1, seconds)
        case .providerDefault, .minutes5, .none:
            return 300
        }
    }
}
