import Foundation

extension FireworksAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let ids = try await fetchServerlessCatalogModelIDs()
        return ids.map { makeModelInfo(id: $0) }
    }

    private var modelsBaseURLRoot: String {
        let strippedInferencePath = baseURL.replacingOccurrences(
            of: "/inference/v1",
            with: "",
            options: [.caseInsensitive, .anchored, .backwards]
        )
        return stripTrailingV1(strippedInferencePath)
    }

    private func fetchServerlessCatalogModelIDs() async throws -> [String] {
        var pageToken: String?
        var ids: [String] = []
        var seenIDs = Set<String>()

        while true {
            let request = makeGETRequest(
                url: try serverlessModelsURL(pageToken: pageToken),
                apiKey: apiKey,
                accept: nil,
                includeUserAgent: false
            )

            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder().decode(FireworksModelsListResponse.self, from: data)

            for model in response.models {
                let id = normalizedServerlessCatalogModelID(model.name)
                if seenIDs.insert(id).inserted {
                    ids.append(id)
                }
            }

            guard let nextPageToken = normalizedPageToken(response.nextPageToken),
                  nextPageToken != pageToken else {
                break
            }
            pageToken = nextPageToken
        }

        return ids
    }

    private func serverlessModelsURL(pageToken: String?) throws -> URL {
        guard var components = URLComponents(
            string: "\(modelsBaseURLRoot)/v1/accounts/fireworks/models"
        ) else {
            throw LLMError.invalidRequest(message: "Invalid Fireworks models URL.")
        }

        var queryItems = [
            URLQueryItem(name: "filter", value: "supports_serverless=true"),
            URLQueryItem(name: "pageSize", value: "200")
        ]
        if let pageToken = normalizedPageToken(pageToken) {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Invalid Fireworks models URL.")
        }
        return url
    }

    private func normalizedServerlessCatalogModelID(_ rawID: String) -> String {
        let trimmed = rawID.trimmed
        let lower = trimmed.lowercased()
        let prefix = "accounts/fireworks/models/"

        if lower.hasPrefix(prefix) {
            let suffix = String(lower.dropFirst(prefix.count))
            if suffix == "deepseek-v4-pro" {
                return "accounts/fireworks/models/\(suffix)"
            }
            return "fireworks/\(suffix)"
        }

        return trimmed
    }

    private func normalizedPageToken(_ pageToken: String?) -> String? {
        pageToken?.trimmedNonEmpty
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .fireworks) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .fireworks)
        }
        return Self.fireworksFallbackModelInfo(id: id, canonical: fireworksCanonicalModelID(id))
    }

    /// Capability/window/name table for serverless models the API returns that are not
    /// in the curated `ModelCatalog`. Keyed by canonical Fireworks model id; the lookup
    /// is single-valued (each id canonicalizes to exactly one key), so a dictionary is
    /// equivalent to the previous ordered if/else ladder. Pinned by FireworksFallbackModelInfoTests.
    static func fireworksFallbackModelInfo(id: String, canonical: String?) -> ModelInfo {
        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?
        var contextWindow = 128_000
        var name = id

        if let canonical, let spec = fireworksFallbackSpecs[canonical] {
            caps.formUnion(spec.extraCapabilities)
            if spec.reasoning {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            if let window = spec.contextWindow { contextWindow = window }
            if let specName = spec.name { name = specName }
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private struct FireworksFallbackSpec {
        var name: String?
        var contextWindow: Int?
        var extraCapabilities: ModelCapability = []
        var reasoning: Bool = false
    }

    private static let fireworksFallbackSpecs: [String: FireworksFallbackSpec] = [
        "qwen3-omni-30b-a3b-instruct": FireworksFallbackSpec(extraCapabilities: [.vision, .audio]),
        "qwen3-omni-30b-a3b-thinking": FireworksFallbackSpec(extraCapabilities: [.vision, .audio]),
        "qwen3-asr-4b": FireworksFallbackSpec(extraCapabilities: [.audio]),
        "qwen3-asr-0.6b": FireworksFallbackSpec(extraCapabilities: [.audio]),
        "qwen3p6-plus": FireworksFallbackSpec(name: "Qwen3.6 Plus", contextWindow: 128_000, extraCapabilities: [.vision]),
        "deepseek-v3p2": FireworksFallbackSpec(name: "DeepSeek V3.2", contextWindow: 163_800),
        "kimi-k2-instruct-0905": FireworksFallbackSpec(name: "Kimi K2 Instruct 0905", contextWindow: 262_100),
        "kimi-k3": FireworksFallbackSpec(
            name: "Kimi K3",
            contextWindow: 1_048_576,
            extraCapabilities: [.vision],
            reasoning: true
        ),
        "kimi-k3-fast": FireworksFallbackSpec(
            name: "Kimi K3 Fast",
            contextWindow: 1_048_576,
            extraCapabilities: [.vision],
            reasoning: true
        ),
        "kimi-k2p6": FireworksFallbackSpec(name: "Kimi K2.6", contextWindow: 262_100, extraCapabilities: [.vision], reasoning: true),
        "kimi-k2p5": FireworksFallbackSpec(name: "Kimi K2.5", contextWindow: 262_100, extraCapabilities: [.vision], reasoning: true),
        "qwen3-235b-a22b": FireworksFallbackSpec(name: "Qwen3 235B A22B", contextWindow: 131_100),
        "qwen3-8b": FireworksFallbackSpec(name: "Qwen3 8B", contextWindow: 40_960),
        "llama-v3p3-70b-instruct": FireworksFallbackSpec(name: "Llama 3.3 70B Instruct", contextWindow: 131_072),
        "minimax-m2p7": FireworksFallbackSpec(name: "MiniMax M2.7", contextWindow: 196_608, reasoning: true),
        "minimax-m2p5": FireworksFallbackSpec(name: "MiniMax M2.5", contextWindow: 196_600, reasoning: true),
        "minimax-m2p1": FireworksFallbackSpec(name: "MiniMax M2.1", contextWindow: 204_800, reasoning: true),
        "minimax-m2": FireworksFallbackSpec(name: "MiniMax M2", contextWindow: 196_600, reasoning: true),
        "glm-5p2": FireworksFallbackSpec(name: "GLM-5.2", contextWindow: 1_040_384, reasoning: true),
        "glm-5p1": FireworksFallbackSpec(name: "GLM-5.1", contextWindow: 202_752, reasoning: true),
        "glm-5": FireworksFallbackSpec(name: "GLM-5", contextWindow: 202_800, reasoning: true),
        "glm-4p7": FireworksFallbackSpec(name: "GLM-4.7", contextWindow: 202_800, reasoning: true),
    ]
}

private struct FireworksModelsListResponse: Decodable {
    let models: [FireworksCatalogModel]
    let nextPageToken: String?
}

private struct FireworksCatalogModel: Decodable {
    let name: String
}
