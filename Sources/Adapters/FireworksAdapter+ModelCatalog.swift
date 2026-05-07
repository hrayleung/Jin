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

        // Fallback heuristics for unknown models returned by the API.
        let isQwen36Plus = isFireworksModelID(id, canonicalID: "qwen3p6-plus")
        let isDeepSeekV3p2 = isFireworksModelID(id, canonicalID: "deepseek-v3p2")
        let isKimiK2Instruct0905 = isFireworksModelID(id, canonicalID: "kimi-k2-instruct-0905")
        let isKimiK2p6 = isFireworksModelID(id, canonicalID: "kimi-k2p6")
        let isKimiK2p5 = isFireworksModelID(id, canonicalID: "kimi-k2p5")
        let isGLM4p7 = isFireworksModelID(id, canonicalID: "glm-4p7")
        let isGLM5 = isFireworksModelID(id, canonicalID: "glm-5")
        let isMiniMaxM2 = isFireworksModelID(id, canonicalID: "minimax-m2")
        let isMiniMaxM2p1 = isFireworksModelID(id, canonicalID: "minimax-m2p1")
        let isMiniMaxM2p5 = isFireworksModelID(id, canonicalID: "minimax-m2p5")
        let isQwen3235 = isFireworksModelID(id, canonicalID: "qwen3-235b-a22b")
        let isQwen3OmniInstruct = isFireworksModelID(id, canonicalID: "qwen3-omni-30b-a3b-instruct")
        let isQwen3OmniThinking = isFireworksModelID(id, canonicalID: "qwen3-omni-30b-a3b-thinking")
        let isQwen3ASR4B = isFireworksModelID(id, canonicalID: "qwen3-asr-4b")
        let isQwen3ASR06B = isFireworksModelID(id, canonicalID: "qwen3-asr-0.6b")

        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?
        var contextWindow = 128_000
        var name = id

        if isQwen3OmniInstruct || isQwen3OmniThinking {
            caps.insert(.vision)
            caps.insert(.audio)
        } else if isQwen3ASR4B || isQwen3ASR06B {
            caps.insert(.audio)
        } else if isQwen36Plus {
            caps.insert(.vision)
            contextWindow = 128_000
            name = "Qwen3.6 Plus"
        } else if isDeepSeekV3p2 {
            contextWindow = 163_800
            name = "DeepSeek V3.2"
        } else if isKimiK2Instruct0905 {
            contextWindow = 262_100
            name = "Kimi K2 Instruct 0905"
        } else if isKimiK2p6 {
            caps.insert(.vision)
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 262_100
            name = "Kimi K2.6"
        } else if isKimiK2p5 {
            caps.insert(.vision)
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 262_100
            name = "Kimi K2.5"
        } else if isQwen3235 {
            contextWindow = 131_100
            name = "Qwen3 235B A22B"
        } else if isMiniMaxM2p5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 196_600
            name = "MiniMax M2.5"
        } else if isMiniMaxM2p1 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 204_800
            name = "MiniMax M2.1"
        } else if isMiniMaxM2 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 196_600
            name = "MiniMax M2"
        } else if isGLM5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 202_800
            name = "GLM-5"
        } else if isGLM4p7 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 202_800
            name = "GLM-4.7"
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }
}

private struct FireworksModelsListResponse: Decodable {
    let models: [FireworksCatalogModel]
    let nextPageToken: String?
}

private struct FireworksCatalogModel: Decodable {
    let name: String
}
