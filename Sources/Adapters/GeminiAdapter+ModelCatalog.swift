import Foundation

extension GeminiAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager,
            authHeader: (key: "x-goog-api-key", value: key)
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var pageToken: String?
        var models: [ModelInfo] = []
        var seenIDs: Set<String> = []

        while true {
            let request = NetworkRequestFactory.makeRequest(
                url: try modelsURL(pageToken: pageToken),
                headers: geminiHeaders()
            )

            let (data, _) = try await networkManager.sendRequest(request)
            let response = try decodeModelsList(from: data)

            for model in response.models {
                let info = makeModelInfo(from: model)
                guard !seenIDs.contains(info.id) else { continue }
                seenIDs.insert(info.id)
                models.append(info)
            }

            guard let next = response.nextPageToken,
                  !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  next != pageToken else {
                break
            }

            pageToken = next
        }

        return models.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func modelsURL(pageToken: String?) throws -> URL {
        var components = URLComponents(string: "\(baseURL)/models")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pageSize", value: "1000")
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid Gemini models URL")
        }
        return url
    }

    private func decodeModelsList(from data: Data) throws -> GeminiListModelsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GeminiListModelsResponse.self, from: data)
    }

    private func makeModelInfo(from model: GeminiListModelsResponse.GeminiModel) -> ModelInfo {
        let id = model.id
        if ModelCatalog.entry(for: id, provider: .gemini) != nil {
            return ModelCatalog.modelInfo(
                for: id,
                provider: .gemini,
                name: model.displayName ?? id
            )
        }

        let lower = id.lowercased()
        let methods = Set(model.supportedGenerationMethods?.map { $0.lowercased() } ?? [])

        var caps: ModelCapability = []

        let supportsGenerateContent = methods.contains("generatecontent") || methods.contains("streamgeneratecontent") || methods.isEmpty
        let supportsStream = methods.contains("streamgeneratecontent") || methods.isEmpty

        if supportsStream {
            caps.insert(.streaming)
        }

        let isImageModel = isImageGenerationModel(id)
        let isGeminiModel = GeminiModelConstants.knownModelIDs.contains(lower)

        if supportsGenerateContent && !isImageModel {
            caps.insert(.toolCalling)
        }

        if isGeminiModel || isImageModel {
            caps.insert(.vision)
        }

        if supportsGenerateContent && isGeminiModel && !isImageModel {
            caps.insert(.audio)
        }

        var reasoningConfig: ModelReasoningConfig?
        if supportsThinking(id) && isGeminiModel {
            caps.insert(.reasoning)
            if lower == "gemini-3.1-flash-image-preview"
                || lower == "gemini-3.1-flash-lite-preview" {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .minimal)
            } else if supportsThinkingConfig(id) {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            } else {
                reasoningConfig = nil
            }
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if !isImageModel {
            caps.insert(.promptCaching)
        }

        if ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: id) {
            caps.insert(.codeExecution)
        }

        if isImageModel {
            caps.insert(.imageGeneration)
        }

        if isVideoGenerationModel(id) {
            caps.insert(.videoGeneration)
        }

        let contextWindow: Int
        if let inputTokenLimit = model.inputTokenLimit {
            contextWindow = inputTokenLimit
        } else if lower == "gemini-3-pro-image-preview" {
            contextWindow = 65_536
        } else if lower == "gemini-3.1-flash-image-preview" {
            contextWindow = 131_072
        } else if lower == "gemini-2.5-flash-image" {
            contextWindow = 32_768
        } else {
            contextWindow = 1_048_576
        }

        return ModelInfo(
            id: id,
            name: model.displayName ?? id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }
}
