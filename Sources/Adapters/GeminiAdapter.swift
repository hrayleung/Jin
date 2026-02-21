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
    private static let gemini3ModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
    ]
    private static let gemini3ProModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-pro-image-preview",
    ]
    private static let geminiImageGenerationModelIDs: Set<String> = [
        "gemini-3-pro-image-preview",
        "gemini-2.5-flash-image",
    ]
    private static let geminiKnownModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-image",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    private let networkManager: NetworkManager
    private let apiKey: String

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
        var request = URLRequest(url: URL(string: "\(baseURL)/cachedContents")!)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(CachedContentsListResponse.self, from: data)
        return response.cachedContents ?? []
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let path = normalizedCachedContentName(name)
        var request = URLRequest(url: URL(string: "\(baseURL)/\(path)")!)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/cachedContents")!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(normalizedCachedContentName(name))")!)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
            let response = try decoder.decode(GenerateContentResponse.self, from: data)

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
                            let chunk = try decoder.decode(GenerateContentResponse.self, from: jsonData)

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
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "x-goog-api-key")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
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

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ListModelsResponse.self, from: data)

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

    private var baseURL: String {
        providerConfig.baseURL ?? ProviderType.gemini.defaultBaseURL ?? "https://generativelanguage.googleapis.com/v1beta"
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

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "contents": translateContents(messages, supportsNativePDF: nativePDFEnabled),
            "generationConfig": buildGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = (controls.contextCache?.mode == .explicit)
            ? normalizedContextCacheString(controls.contextCache?.cachedContentName)
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
            deepMerge(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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

    private func modelIDForPath(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private func normalizedContextCacheString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedCachedContentName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cachedcontents/") {
            return trimmed
        }
        return "cachedContents/\(trimmed)"
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        isGemini3Model(modelID) && !isImageGenerationModel(modelID)
    }

    private func isGemini3Model(_ modelID: String) -> Bool {
        Self.gemini3ModelIDs.contains(modelID.lowercased())
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        Self.geminiImageGenerationModelIDs.contains(modelID.lowercased())
    }

    private func isVideoGenerationModel(_ modelID: String) -> Bool {
        GoogleVideoGenerationCore.isVideoGenerationModel(modelID)
    }

    // MARK: - Video Generation (Veo)

    private func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let prompt = GoogleVideoGenerationCore.extractPrompt(from: messages) else {
            throw LLMError.invalidRequest(message: "Video generation requires a text prompt.")
        }

        let imageInput = GoogleVideoGenerationCore.extractImageInput(from: messages)
        let videoControls = controls.googleVideoGeneration

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // 1. Build and submit the generation request
                    let modelPath = modelIDForPath(modelID)
                    let endpoint = "\(baseURL)/models/\(modelPath):predictLongRunning"
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                    var instance: [String: Any] = ["prompt": prompt]

                    if let image = imageInput,
                       let base64 = GoogleVideoGenerationCore.imageToBase64(image) {
                        instance["image"] = [
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": base64
                            ]
                        ]
                    }

                    let parameters = GoogleVideoGenerationCore.buildGeminiParameters(
                        controls: videoControls,
                        modelID: modelID
                    )

                    let body: [String: Any] = [
                        "instances": [instance],
                        "parameters": parameters
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (startData, _) = try await networkManager.sendRequest(request)
                    let rawStart = try? JSONSerialization.jsonObject(with: startData) as? [String: Any]
                    guard let operationName = rawStart?["name"] as? String, !operationName.isEmpty else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "Gemini video generation did not return an operation name. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: operationName))

                    // 2. Poll until done
                    let pollIntervalNanoseconds: UInt64 = 10_000_000_000 // 10 seconds
                    let maxAttempts = 60 // ~10 minutes at 10s intervals

                    for attempt in 0..<maxAttempts {
                        try Task.checkCancellation()

                        if attempt > 0 {
                            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                        }

                        var pollRequest = URLRequest(url: URL(string: "\(baseURL)/\(operationName)")!)
                        pollRequest.httpMethod = "GET"
                        pollRequest.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

                        let (pollData, pollResponse) = try await networkManager.sendRawRequest(pollRequest)
                        let pollJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any]

                        // Check for error in operation
                        if let error = pollJSON?["error"] as? [String: Any] {
                            let message = error["message"] as? String ?? "Video generation failed."
                            throw LLMError.providerError(code: "video_generation_failed", message: message)
                        }

                        // Non-2xx HTTP means something went wrong
                        if pollResponse.statusCode >= 400 {
                            let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                            throw LLMError.providerError(
                                code: "video_poll_error",
                                message: "Polling returned HTTP \(pollResponse.statusCode): \(String(raw.prefix(500)))"
                            )
                        }

                        let done = pollJSON?["done"] as? Bool ?? false
                        guard done else { continue }

                        // 3. Extract video URI from response
                        guard let response = pollJSON?["response"] as? [String: Any],
                              let generateVideoResponse = response["generateVideoResponse"] as? [String: Any],
                              let generatedSamples = generateVideoResponse["generatedSamples"] as? [[String: Any]],
                              let firstSample = generatedSamples.first,
                              let video = firstSample["video"] as? [String: Any],
                              let uriString = video["uri"] as? String,
                              !uriString.isEmpty else {
                            let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                            throw LLMError.decodingError(
                                message: "Gemini video generation completed but no video URI found. Response: \(String(raw.prefix(500)))"
                            )
                        }

                        // 4. Download the video (append API key for authentication)
                        var downloadComponents = URLComponents(string: uriString)
                        var queryItems = downloadComponents?.queryItems ?? []
                        queryItems.append(URLQueryItem(name: "key", value: apiKey))
                        downloadComponents?.queryItems = queryItems

                        guard let downloadURL = downloadComponents?.url else {
                            throw LLMError.decodingError(message: "Invalid video download URI: \(uriString)")
                        }

                        let (localURL, mimeType) = try await GoogleVideoGenerationCore.downloadVideoToLocal(
                            from: downloadURL,
                            networkManager: networkManager
                        )

                        let videoContent = VideoContent(mimeType: mimeType, data: nil, url: localURL)
                        continuation.yield(.contentDelta(.video(videoContent)))
                        continuation.yield(.messageEnd(usage: nil))
                        continuation.finish()
                        return
                    }

                    throw LLMError.providerError(
                        code: "video_generation_timeout",
                        message: "Gemini video generation timed out after polling for ~10 minutes."
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func supportsFunctionCalling(_ modelID: String) -> Bool {
        // Gemini image-generation models do not support function calling.
        !isImageGenerationModel(modelID)
    }

    private func supportsGoogleSearch(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support Google Search grounding.
        if modelID.lowercased() == "gemini-2.5-flash-image" {
            return false
        }
        return true
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
        guard supportsGoogleSearch(modelID) else { return false }

        if let model = configuredModel(for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            return resolved.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerConfig.type,
            modelID: modelID
        )
    }

    private func configuredModel(for modelID: String) -> ModelInfo? {
        if let exact = providerConfig.models.first(where: { $0.id == modelID }) {
            return exact
        }
        let target = modelID.lowercased()
        return providerConfig.models.first(where: { $0.id.lowercased() == target })
    }

    private func supportsImageSize(_ modelID: String) -> Bool {
        // imageSize is documented for Gemini 3 Pro Image.
        modelID.lowercased() == "gemini-3-pro-image-preview"
    }

    private func supportsThinking(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support thinking; Gemini 3 Pro Image does.
        modelID.lowercased() != "gemini-2.5-flash-image"
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
        if supportsThinking(modelID), let reasoning = controls.reasoning {
            if reasoning.enabled {
                var thinkingConfig: [String: Any] = [
                    "includeThoughts": true
                ]

                if let effort = reasoning.effort {
                    thinkingConfig["thinkingLevel"] = mapEffortToThinkingLevel(effort, modelID: modelID)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }

                config["thinkingConfig"] = thinkingConfig
            } else if isGemini3Model(modelID) {
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
            if supportsImageSize(modelID), let imageSize = imageControls?.imageSize {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private func defaultThinkingLevelWhenOff(modelID: String) -> String {
        if Self.gemini3ProModelIDs.contains(modelID.lowercased()) {
            return "LOW"
        }
        return "MINIMAL"
    }

    private func mapEffortToThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        let isPro = Self.gemini3ProModelIDs.contains(modelID.lowercased())

        switch effort {
        case .none:
            return isPro ? "LOW" : "MINIMAL"
        case .minimal:
            return isPro ? "LOW" : "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return isPro ? "HIGH" : "MEDIUM"
        case .high:
            return "HIGH"
        case .xhigh:
            return "HIGH"
        }
    }

    private func translateContents(_ messages: [Message], supportsNativePDF: Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(messages.count + 4)

        for message in messages where message.role != .system {
            switch message.role {
            case .system:
                continue
            case .tool:
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            case .user, .assistant:
                out.append(translateNonToolMessage(message, supportsNativePDF: supportsNativePDF))

                // Some providers/users serialize tool results inline on non-tool messages; handle defensively.
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            }
        }

        return out
    }

    private func translateNonToolMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any] {
        let role: String = (message.role == .assistant) ? "model" : "user"

        var parts: [[String: Any]] = []

        // Preserve thoughts first for model turns to keep tool calling stable when thought signatures are enabled.
        if message.role == .assistant {
            for part in message.content {
                if case .thinking(let thinking) = part {
                    var dict: [String: Any] = [
                        "text": thinking.text,
                        "thought": true
                    ]
                    if let signature = thinking.signature {
                        dict["thoughtSignature"] = signature
                    }
                    parts.append(dict)
                }
            }
        }

        // User-visible content (text/images/files).
        for part in message.content {
            switch part {
            case .text(let text):
                parts.append(["text": text])

            case .image(let image):
                if let inline = inlineDataPart(mimeType: image.mimeType, data: image.data, url: image.url) {
                    parts.append(inline)
                }

            case .video(let video):
                if let inline = inlineDataPart(mimeType: video.mimeType, data: video.data, url: video.url) {
                    parts.append(inline)
                }

            case .audio(let audio):
                if let inline = inlineDataPart(mimeType: audio.mimeType, data: audio.data, url: audio.url) {
                    parts.append(inline)
                }

            case .file(let file):
                // Native PDF support for Gemini 3 series.
                if supportsNativePDF, file.mimeType == "application/pdf" {
                    let pdfData: Data?
                    if let data = file.data {
                        pdfData = data
                    } else if let url = file.url, url.isFileURL {
                        pdfData = try? Data(contentsOf: url)
                    } else {
                        pdfData = nil
                    }

                    if let pdfData {
                        parts.append([
                            "inlineData": [
                                "mimeType": "application/pdf",
                                "data": pdfData.base64EncodedString()
                            ]
                        ])
                        continue
                    }
                }

                // Fallback to text extraction.
                let text = AttachmentPromptRenderer.fallbackText(for: file)
                parts.append(["text": text])

            case .thinking, .redactedThinking:
                continue
            }
        }

        // Function calls (model output) are appended to model turns.
        if message.role == .assistant, let toolCalls = message.toolCalls {
            for call in toolCalls {
                var part: [String: Any] = [
                    "functionCall": [
                        "name": call.name,
                        "args": call.arguments.mapValues { $0.value }
                    ]
                ]
                if let signature = call.signature {
                    part["thoughtSignature"] = signature
                }
                parts.append(part)
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": role,
            "parts": parts
        ]
    }

    private func translateToolResults(_ results: [ToolResult]) -> [String: Any] {
        var parts: [[String: Any]] = []
        parts.reserveCapacity(results.count)

        for result in results {
            guard let toolName = result.toolName, !toolName.isEmpty else { continue }

            var part: [String: Any] = [
                "functionResponse": [
                    "name": toolName,
                    "response": [
                        "content": result.content
                    ]
                ]
            ]

            if let signature = result.signature {
                part["thoughtSignature"] = signature
            }

            parts.append(part)
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": "user",
            "parts": parts
        ]
    }

    private func inlineDataPart(mimeType: String, data: Data?, url: URL?) -> [String: Any]? {
        if let data {
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        if let url {
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return [
                    "inlineData": [
                        "mimeType": mimeType,
                        "data": data.base64EncodedString()
                    ]
                ]
            }
        }

        return nil
    }

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

    private func events(from part: GenerateContentResponse.Part) -> [StreamEvent] {
        var out: [StreamEvent] = []

        if part.thought == true {
            let text = part.text ?? ""
            let signature = part.thoughtSignature
            if !text.isEmpty || signature != nil {
                out.append(.thinkingDelta(.thinking(textDelta: text, signature: signature)))
            }
        } else if let text = part.text, !text.isEmpty {
            out.append(.contentDelta(.text(text)))
        }

        if let inline = part.inlineData,
           let base64 = inline.data,
           let data = Data(base64Encoded: base64) {
            let mimeType = inline.mimeType ?? "image/png"
            if mimeType.lowercased().hasPrefix("image/") {
                out.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
            }
        }

        if let functionCall = part.functionCall {
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: functionCall.name,
                arguments: functionCall.args ?? [:],
                signature: part.thoughtSignature
            )
            out.append(.toolCallStart(toolCall))
            out.append(.toolCallEnd(toolCall))
        }

        return out
    }

    private func searchActivities(from grounding: GenerateContentResponse.GroundingMetadata?) -> [StreamEvent] {
        GoogleGroundingSearchActivities.events(
            from: grounding.map(toSharedGrounding),
            searchPrefix: "gemini-search",
            openPrefix: "gemini-open",
            searchURLPrefix: "gemini-search-url"
        )
    }

    private func candidateGroundingMetadata(in candidates: [GenerateContentResponse.Candidate]?) -> GenerateContentResponse.GroundingMetadata? {
        guard let candidates else { return nil }
        for candidate in candidates {
            if let grounding = candidate.groundingMetadata {
                return grounding
            }
        }
        return nil
    }

    private func toSharedGrounding(_ g: GenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: g.webSearchQueries,
            retrievalQueries: g.retrievalQueries,
            groundingChunks: g.groundingChunks?.map {
                .init(webURI: $0.web?.uri, webTitle: $0.web?.title)
            },
            groundingSupports: g.groundingSupports?.map {
                .init(segmentText: $0.segment?.text, groundingChunkIndices: $0.groundingChunkIndices)
            },
            searchEntryPoint: g.searchEntryPoint.map {
                .init(sdkBlob: $0.sdkBlob)
            }
        )
    }

    private func isCandidateContentFiltered(_ candidate: GenerateContentResponse.Candidate) -> Bool {
        // Gemini can signal blocks via finishReason. Treat safety/blocked as filtered.
        let reason = (candidate.finishReason ?? "").uppercased()
        if reason == "SAFETY" || reason == "BLOCKED" || reason == "PROHIBITED_CONTENT" {
            return true
        }
        return false
    }

    private func makeModelInfo(from model: ListModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let methods = Set(model.supportedGenerationMethods?.map { $0.lowercased() } ?? [])

        var caps: ModelCapability = []

        let supportsGenerateContent = methods.contains("generatecontent") || methods.contains("streamgeneratecontent") || methods.isEmpty
        let supportsStream = methods.contains("streamgeneratecontent") || methods.isEmpty

        if supportsStream {
            caps.insert(.streaming)
        }

        let isImageModel = isImageGenerationModel(id)
        let isGeminiModel = Self.geminiKnownModelIDs.contains(lower)

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
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if !isImageModel {
            caps.insert(.promptCaching)
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

    private func deepMerge(into base: inout [String: Any], additional: [String: Any]) {
        for (key, value) in additional {
            if var baseDict = base[key] as? [String: Any],
               let addDict = value as? [String: Any] {
                deepMerge(into: &baseDict, additional: addDict)
                base[key] = baseDict
                continue
            }
            base[key] = value
        }
    }
}

// MARK: - DTOs

private struct CachedContentsListResponse: Codable {
    let cachedContents: [GeminiAdapter.CachedContentResource]?
    let nextPageToken: String?
}

private struct ListModelsResponse: Codable {
    let models: [Model]
    let nextPageToken: String?

    struct Model: Codable {
        let name: String
        let displayName: String?
        let description: String?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
        let supportedGenerationMethods: [String]?

        var id: String {
            if name.lowercased().hasPrefix("models/") {
                return String(name.dropFirst("models/".count))
            }
            return name
        }
    }
}

private struct GenerateContentResponse: Codable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?
    let groundingMetadata: GroundingMetadata?

    struct Candidate: Codable {
        let content: Content?
        let finishReason: String?
        let groundingMetadata: GroundingMetadata?
    }

    struct Content: Codable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Codable {
        let text: String?
        let thought: Bool?
        let thoughtSignature: String?
        let functionCall: FunctionCall?
        let functionResponse: FunctionResponse?
        let inlineData: InlineData?
    }

    struct InlineData: Codable {
        let mimeType: String?
        let data: String?
    }

    struct FunctionCall: Codable {
        let name: String
        let args: [String: AnyCodable]?
    }

    struct FunctionResponse: Codable {
        let name: String?
        let response: [String: AnyCodable]?
    }

    struct PromptFeedback: Codable {
        let blockReason: String?
    }

    struct UsageMetadata: Codable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
        let cachedContentTokenCount: Int?
    }

    struct GroundingMetadata: Codable {
        let webSearchQueries: [String]?
        let retrievalQueries: [String]?
        let groundingChunks: [GroundingChunk]?
        let groundingSupports: [GroundingSupport]?
        let searchEntryPoint: SearchEntryPoint?

        struct GroundingChunk: Codable {
            let web: WebChunk?

            struct WebChunk: Codable {
                let uri: String?
                let title: String?
            }
        }

        struct SearchEntryPoint: Codable {
            let renderedContent: String?
            let sdkBlob: String?
        }

        struct GroundingSupport: Codable {
            let segment: Segment?
            let groundingChunkIndices: [Int]?

            struct Segment: Codable {
                let text: String?
            }
        }
    }

    func toUsage() -> Usage? {
        guard let usageMetadata else { return nil }
        guard let input = usageMetadata.promptTokenCount,
              let output = usageMetadata.candidatesTokenCount else {
            return nil
        }
        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: nil,
            cachedTokens: usageMetadata.cachedContentTokenCount
        )
    }
}
