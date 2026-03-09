import Foundation

/// Gemini (AI Studio) provider adapter (Gemini API / Generative Language API).
///
/// This adapter targets Gemini 3 series models via `generateContent` + `streamGenerateContent?alt=sse`.
/// It supports:
/// - Streaming (SSE)
/// - Thinking summaries (thought parts) + thought signatures
/// - Function calling (tools) + tool results
/// - Vision + native PDF (inlineData) for Gemini 3
/// - Grounding with Google Search (`google_search` tool)
actor GeminiAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]
    // Model ID sets are shared with VertexAIAdapter via GeminiModelConstants.

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    struct CachedContentResource: Codable, Hashable, Sendable {
        let name: String
        let model: String?
        let displayName: String?
        let createTime: String?
        let updateTime: String?
        let expireTime: String?
        let usageMetadata: UsageMetadata?

        struct UsageMetadata: Codable, Hashable, Sendable {
            let textCount: Int?
        }
    }

    func listCachedContents() async throws -> [CachedContentResource] {
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/cachedContents"),
            headers: geminiHeaders(accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(GeminiCachedContentsListResponse.self, from: data)
        return response.cachedContents ?? []
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let path = normalizedCachedContentName(name)
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/\(path)"),
            headers: geminiHeaders(accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/cachedContents"),
            headers: geminiHeaders(),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func updateCachedContent(named name: String, payload: [String: Any], updateMask: String? = nil) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        var components = URLComponents(string: "\(baseURL)/\(normalizedCachedContentName(name))")
        if let updateMask {
            components?.queryItems = [URLQueryItem(name: "updateMask", value: updateMask)]
        }
        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent URL.")
        }

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: url,
            method: "PATCH",
            headers: geminiHeaders(),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String) async throws {
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/\(normalizedCachedContentName(name))"),
            method: "DELETE",
            headers: geminiHeaders()
        )
        _ = try await networkManager.sendRequest(request)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(
                messages: messages,
                modelID: modelID,
                controls: controls
            )
        }

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(GeminiGenerateContentResponse.self, from: data)

            // Handle prompt-level blocks explicitly (Gemini returns promptFeedback for blocked prompts).
            if response.promptFeedback?.blockReason != nil {
                throw LLMError.contentFiltered
            }

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: UUID().uuidString))

                let usage = response.toUsage()

                if let candidate = response.candidates?.first {
                    if isCandidateContentFiltered(candidate) {
                        continuation.yield(.error(.contentFiltered))
                        continuation.finish()
                        return
                    }

                    for part in candidate.content?.parts ?? [] {
                        for event in events(from: part) {
                            continuation.yield(event)
                        }
                    }
                }

                let grounding = candidateGroundingMetadata(in: response.candidates) ?? response.groundingMetadata
                for event in searchActivities(from: grounding) {
                    continuation.yield(event)
                }

                continuation.yield(.messageEnd(usage: usage))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    let messageID = UUID().uuidString
                    var pendingUsage: Usage?

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8) else { continue }

                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            let chunk = try decoder.decode(GeminiGenerateContentResponse.self, from: jsonData)

                            if chunk.promptFeedback?.blockReason != nil {
                                continuation.yield(.error(.contentFiltered))
                                continuation.finish()
                                return
                            }

                            if !didStart {
                                didStart = true
                                continuation.yield(.messageStart(id: messageID))
                            }

                            if let usage = chunk.toUsage() {
                                pendingUsage = usage
                            }

                            if let candidate = chunk.candidates?.first {
                                if isCandidateContentFiltered(candidate) {
                                    continuation.yield(.error(.contentFiltered))
                                    continuation.finish()
                                    return
                                }

                                for part in candidate.content?.parts ?? [] {
                                    for streamEvent in events(from: part) {
                                        continuation.yield(streamEvent)
                                    }
                                }
                            }

                            let grounding = candidateGroundingMetadata(in: chunk.candidates) ?? chunk.groundingMetadata
                            for streamEvent in searchActivities(from: grounding) {
                                continuation.yield(streamEvent)
                            }

                        case .done:
                            // Gemini SSE streams typically end by closing the connection (no [DONE]),
                            // but handle it anyway for compatibility.
                            break
                        }
                    }

                    if didStart {
                        continuation.yield(.messageEnd(usage: pendingUsage))
                    } else {
                        // No chunks were received at all — emit an error so callers
                        // don't silently succeed with an empty conversation.
                        continuation.yield(.messageStart(id: messageID))
                        continuation.yield(.error(.decodingError(message: "Gemini returned an empty response with no content.")))
                        continuation.yield(.messageEnd(usage: nil))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

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

            let request = NetworkRequestFactory.makeRequest(
                url: url,
                headers: geminiHeaders()
            )

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(GeminiListModelsResponse.self, from: data)

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

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    var baseURL: String {
        providerConfig.baseURL ?? ProviderType.gemini.defaultBaseURL ?? "https://generativelanguage.googleapis.com/v1beta"
    }

    func geminiHeaders(apiKey: String? = nil, accept: String? = nil, contentType: String? = nil) -> [String: String] {
        var headers: [String: String] = ["x-goog-api-key": apiKey ?? self.apiKey]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let modelPath = modelIDForPath(modelID)
        let method = streaming ? "streamGenerateContent?alt=sse" : "generateContent"
        let endpoint = "\(baseURL)/models/\(modelPath):\(method)"

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "contents": try translateContents(messages, supportsNativePDF: nativePDFEnabled),
            "generationConfig": buildGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = (controls.contextCache?.mode == .explicit)
            ? normalizedTrimmedString(controls.contextCache?.cachedContentName)
            : nil

        if explicitCachedContent == nil, let systemInstruction = systemInstructionText(from: messages) {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        if let cachedContent = explicitCachedContent {
            body["cachedContent"] = cachedContent
        }

        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            toolArray.append(["google_search": [:]])
        }

        if supportsFunctionCalling(modelID), !tools.isEmpty,
           let functionDeclarations = translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL(endpoint),
            headers: geminiHeaders(),
            body: body
        )
    }

    private func systemInstructionText(from messages: [Message]) -> String? {
        let text = messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .compactMap { part -> String? in
                if case .text(let text) = part { return text }
                return nil
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    func modelIDForPath(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private func normalizedCachedContentName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cachedcontents/") {
            return trimmed
        }
        return "cachedContents/\(trimmed)"
    }

    func supportsNativePDF(_ modelID: String) -> Bool {
        GeminiModelConstants.supportsNativePDF(modelID)
    }

    func isGemini3Model(_ modelID: String) -> Bool {
        GeminiModelConstants.isGemini3Model(modelID)
    }

    func isImageGenerationModel(_ modelID: String) -> Bool {
        GeminiModelConstants.isImageGenerationModel(modelID)
    }

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        GoogleVideoGenerationCore.isVideoGenerationModel(modelID)
    }

    private func supportsFunctionCalling(_ modelID: String) -> Bool {
        // Gemini image-generation models do not support function calling.
        !isImageGenerationModel(modelID)
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsImageSize(_ modelID: String) -> Bool {
        // imageSize is documented for Gemini 3 Pro Image and Gemini 3.1 Flash Image.
        let lower = modelID.lowercased()
        return lower == "gemini-3-pro-image-preview" || lower == "gemini-3.1-flash-image-preview"
    }

    private func supportsImageSize(_ modelID: String, imageSize: ImageOutputSize) -> Bool {
        guard supportsImageSize(modelID) else { return false }
        let lower = modelID.lowercased()
        if lower == "gemini-3-pro-image-preview" {
            return imageSize != .size512px
        }
        return true
    }

    func supportsThinking(_ modelID: String) -> Bool {
        modelID.lowercased() != "gemini-2.5-flash-image"
    }

    func supportsThinkingConfig(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return supportsThinking(modelID) && lower != "gemini-3-pro-image-preview"
    }

    func supportsThinkingLevel(_ modelID: String) -> Bool {
        supportsThinkingConfig(modelID)
    }

    private func buildGenerationConfig(_ controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        let isImageModel = isImageGenerationModel(modelID)

        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }

        // Gemini 3: dynamic thinking is on by default; thinkingLevel controls the amount of thinking.
        if supportsThinkingConfig(modelID), let reasoning = controls.reasoning {
            if reasoning.enabled {
                var thinkingConfig: [String: Any] = [
                    "includeThoughts": true
                ]

                if let effort = reasoning.effort, supportsThinkingLevel(modelID) {
                    let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                        effort,
                        for: .gemini,
                        modelID: modelID
                    )
                    thinkingConfig["thinkingLevel"] = mapEffortToThinkingLevel(normalizedEffort, modelID: modelID)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }

                config["thinkingConfig"] = thinkingConfig
            } else if isGemini3Model(modelID), supportsThinkingLevel(modelID) {
                // Best-effort "off": minimize thinking level (cannot be fully disabled for Gemini 3 Pro).
                config["thinkingConfig"] = [
                    "thinkingLevel": defaultThinkingLevelWhenOff(modelID: modelID)
                ]
            }
        }

        if isImageModel {
            let imageControls = controls.imageGeneration
            let responseMode = imageControls?.responseMode ?? .textAndImage
            config["responseModalities"] = responseMode.responseModalities

            if let seed = imageControls?.seed {
                config["seed"] = seed
            }

            var imageConfig: [String: Any] = [:]
            if let aspectRatio = imageControls?.aspectRatio {
                imageConfig["aspectRatio"] = aspectRatio.rawValue
            }
            if let imageSize = imageControls?.imageSize, supportsImageSize(modelID, imageSize: imageSize) {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private func defaultThinkingLevelWhenOff(modelID: String) -> String {
        GeminiModelConstants.defaultThinkingLevelWhenOff(for: .gemini, modelID: modelID)
    }

    private func mapEffortToThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        GeminiModelConstants.mapEffortToThinkingLevel(effort, for: .gemini, modelID: modelID)
    }

    // Content translation, event parsing, and model info building are in GeminiContentTranslation.swift

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

}

// Content translation, event parsing, model info: GeminiContentTranslation.swift
// Video generation: GeminiVideoGeneration.swift
// DTOs: GeminiAdapterResponseTypes.swift
