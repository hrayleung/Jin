import Foundation

extension OpenRouterAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/key"),
            apiKey: key,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let standardModels = try await fetchStandardModels()
        let videoModels = await fetchVideoModelsIfAvailable()

        var seenIDs = Set<String>()
        return (standardModels + videoModels).filter { model in
            seenIDs.insert(model.id).inserted
        }
    }

    func fetchStandardModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    func fetchVideoModelsIfAvailable() async -> [ModelInfo] {
        do {
            return try await fetchVideoModels()
        } catch {
            return []
        }
    }

    func fetchVideoModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/videos/models"),
            apiKey: apiKey,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterVideoModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    func makeModelInfo(from model: OpenRouterModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let apiContextWindow = positiveInt(model.contextLength)
            ?? positiveInt(model.topProvider?.contextLength)
        let apiMaxOutputTokens = positiveInt(model.topProvider?.maxCompletionTokens)

        if let entry = ModelCatalog.entry(for: id, provider: .openrouter) {
            return ModelInfo(
                id: id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: apiContextWindow ?? entry.contextWindow,
                maxOutputTokens: apiMaxOutputTokens ?? entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        let inputModalities = Set((model.architecture?.inputModalities ?? []).map { $0.lowercased() })
        let outputModalities = Set((model.architecture?.outputModalities ?? []).map { $0.lowercased() })
        let supportedParameters = Set((model.supportedParameters ?? []).map { $0.lowercased() })
        let hasImageLikeModalities = inputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
            || outputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
        let hasAudioLikeModalities = inputModalities.contains(where: { $0.contains("audio") })
            || outputModalities.contains(where: { $0.contains("audio") })
        let supportsReasoning = supportedParameters.contains("reasoning")
            || supportedParameters.contains("include_reasoning")
            || supportedParameters.contains("reasoning_effort")
        let outputsText = outputModalities.contains(where: { $0.contains("text") })
        let outputsImage = outputModalities.contains(where: { $0.contains("image") }) || lower.contains("image")
        let outputsVideo = outputModalities.contains(where: { $0.contains("video") }) || lower.contains("video")
        let isMediaOnlyModel = (outputsImage || outputsVideo) && !outputsText

        var caps: ModelCapability = isMediaOnlyModel ? [] : [.streaming]

        if !isMediaOnlyModel, supportedParameters.contains("tools") {
            caps.insert(.toolCalling)
        }
        if hasImageLikeModalities {
            caps.insert(.vision)
        }
        if !isMediaOnlyModel, hasAudioLikeModalities || isAudioInputModelID(lower) {
            caps.insert(.audio)
        }
        if !isMediaOnlyModel, supportsReasoning {
            caps.insert(.reasoning)
        }
        if !isMediaOnlyModel, model.pricing?.inputCacheRead != nil {
            caps.insert(.promptCaching)
        }
        if outputsImage {
            caps.insert(.imageGeneration)
        }
        if outputsVideo {
            caps.insert(.videoGeneration)
        }

        return ModelInfo(
            id: id,
            name: model.name ?? id,
            capabilities: caps,
            contextWindow: apiContextWindow ?? 128_000,
            maxOutputTokens: apiMaxOutputTokens,
            reasoningConfig: (!isMediaOnlyModel && supportsReasoning)
                ? ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                : nil
        )
    }

    func makeModelInfo(from model: OpenRouterVideoModelsResponse.Model) -> ModelInfo {
        let id = model.id

        if let entry = ModelCatalog.entry(for: id, provider: .openrouter) {
            return ModelInfo(
                id: id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        return ModelInfo(
            id: id,
            name: model.name ?? id,
            capabilities: [.videoGeneration],
            contextWindow: 32_768,
            maxOutputTokens: nil,
            reasoningConfig: nil
        )
    }

    func positiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let name: String?
        let contextLength: Int?
        let architecture: Architecture?
        let topProvider: TopProvider?
        let supportedParameters: [String]?
        let pricing: Pricing?
    }

    struct Architecture: Decodable {
        let inputModalities: [String]?
        let outputModalities: [String]?
    }

    struct TopProvider: Decodable {
        let contextLength: Int?
        let maxCompletionTokens: Int?
    }

    struct Pricing: Decodable {
        let inputCacheRead: String?
    }
}

struct OpenRouterVideoModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let name: String?
    }
}
