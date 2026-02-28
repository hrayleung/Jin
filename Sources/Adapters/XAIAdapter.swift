import Foundation

/// xAI provider adapter.
///
/// - Chat models use the Responses API (`/responses`).
/// - Image models use `/images/generations` + `/images/edits`.
/// - Video models use `/videos/generations` (text/image) and `/videos/edits` (video edit), both async.
actor XAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .imageGeneration, .videoGeneration]
    private static let chatReasoningModelIDs: Set<String> = [
        "grok-4",
        "grok-4-1",
        "grok-4-1-fast",
        "grok-4-1-fast-non-reasoning",
        "grok-4-1-fast-reasoning",
        "grok-4-1212",
    ]
    private static let imageGenerationModelIDs: Set<String> = [
        "grok-imagine-image",
        "grok-imagine-image-pro",
        "grok-2-image-1212",
    ]
    private static let videoGenerationModelIDs: Set<String> = [
        "grok-imagine-video",
    ]
    private static let reasoningEffortModelIDs: Set<String> = [
        "grok-3-mini",
    ]

    private let networkManager: NetworkManager
    private let r2Uploader: CloudflareR2Uploader
    private let apiKey: String

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager(),
        r2Uploader: CloudflareR2Uploader? = nil
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.r2Uploader = r2Uploader ?? CloudflareR2Uploader(networkManager: networkManager)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        if isImageGenerationModel(modelID) {
            return try makeImageGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        return try await sendResponsesConversation(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: try validatedURL("\(baseURL)/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: try validatedURL("\(baseURL)/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(XAIModelsResponse.self, from: data)

        return response.data
            .map { model in
                let caps = inferCapabilities(for: model)
                return ModelInfo(
                    id: model.id,
                    name: model.id,
                    capabilities: caps,
                    contextWindow: model.contextWindow ?? 128000,
                    reasoningConfig: nil
                )
            }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.x.ai/v1"
    }

    // MARK: - Chat (Responses API)

    private func sendResponsesConversation(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try buildResponsesRequest(
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
            let response = try decoder.decode(ResponsesAPIResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for text in response.outputTextParts {
                    continuation.yield(.contentDelta(.text(text)))
                }

                let outputText = response.outputTextParts.joined(separator: "\n")
                if let citationActivity = citationSearchActivity(
                    sources: citationCandidates(
                        citations: response.citations,
                        output: response.output,
                        fallbackText: outputText
                    ),
                    responseID: response.id
                ) {
                    continuation.yield(.searchActivity(citationActivity))
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        let streamDecoder = JSONDecoder()
        streamDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var streamedOutputText = ""

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if type == "response.completed",
                               let jsonData = data.data(using: .utf8),
                               let completed = try? streamDecoder.decode(ResponsesAPICompletedEvent.self, from: jsonData),
                               let citationActivity = citationSearchActivity(
                                   sources: citationCandidates(
                                       citations: completed.response.citations,
                                       output: completed.response.output,
                                       fallbackText: streamedOutputText
                                   ),
                                   responseID: completed.response.id
                               ) {
                                continuation.yield(.searchActivity(citationActivity))
                            }

                            if let streamEvent = try parseSSEEvent(
                                type: type,
                                data: data,
                                functionCallsByItemID: &functionCallsByItemID
                            ) {
                                if case .contentDelta(.text(let delta)) = streamEvent {
                                    streamedOutputText.append(delta)
                                }
                                continuation.yield(streamEvent)
                            }
                        case .done:
                            continuation.yield(.messageEnd(usage: nil))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildResponsesRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try validatedURL("\(baseURL)/responses"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "model": modelID,
            "input": translateInput(messages, supportsNativePDF: nativePDFEnabled),
            "stream": streaming
        ]

        if controls.contextCache?.mode != .off {
            if let conversationID = normalizedTrimmedString(controls.contextCache?.conversationID) {
                request.setValue(conversationID, forHTTPHeaderField: "x-grok-conv-id")
            }
            if let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) {
                body["prompt_cache_key"] = cacheKey
            }
            if let retention = controls.contextCache?.ttl?.providerTTLString {
                body["prompt_cache_retention"] = retention
            }
            if let minTokens = controls.contextCache?.minTokensThreshold, minTokens > 0 {
                body["prompt_cache_min_tokens"] = minTokens
            }
        }

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        if supportsReasoningEffort(modelID: modelID),
           let reasoning = controls.reasoning,
           reasoning.enabled,
           let effort = reasoning.effort {
            body["reasoning_effort"] = mapReasoningEffort(effort)
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID: modelID) {
            let sources = Set(controls.webSearch?.sources ?? [.web])

            if sources.contains(.web) {
                toolObjects.append(["type": "web_search"])
            }

            if sources.contains(.x) {
                toolObjects.append(["type": "x_search"])
            }
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Image generation

    private func makeImageGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let imageURL = imageURLForImageGeneration(from: messages)
        let prompt = try mediaPrompt(
            from: messages,
            mode: imageURL?.isEmpty == false ? .image : .none
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildImageGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        imageURL: imageURL,
                        controls: controls
                    )
                    let (data, _) = try await networkManager.sendRequest(request)

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(XAIImageGenerationResponse.self, from: data)

                    if let error = response.error {
                        throw LLMError.providerError(code: error.code ?? "image_generation_failed", message: error.message)
                    }

                    let images = resolveImageOutputs(from: response.mediaItems)
                    guard !images.isEmpty else {
                        throw LLMError.decodingError(message: "xAI image generation returned no image output.")
                    }

                    continuation.yield(.messageStart(id: response.resolvedID ?? "img_\(UUID().uuidString)"))
                    for image in images {
                        continuation.yield(.contentDelta(.image(image)))
                    }
                    continuation.yield(.messageEnd(usage: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Video generation

    private func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let videoInput = videoInputForVideoGeneration(from: messages)
        let imageURL = imageURLForImageGeneration(from: messages)
        let isVideoToVideo = videoInput != nil
        let isImageToVideo = !isVideoToVideo && imageURL?.isEmpty == false
        let prompt = try mediaPrompt(
            from: messages,
            mode: isVideoToVideo ? .video : (isImageToVideo ? .image : .none)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let resolvedVideoURL = try await resolvedVideoURL(for: videoInput)

                    // 1. Submit generation request
                    let startRequest = try buildVideoGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        imageURL: isImageToVideo ? imageURL : nil,
                        videoURL: isVideoToVideo ? resolvedVideoURL : nil,
                        controls: controls
                    )
                    let (startData, _) = try await networkManager.sendRequest(startRequest)
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let startResponse = try decoder.decode(XAIVideoStartResponse.self, from: startData)

                    if let apiError = startResponse.error {
                        throw LLMError.providerError(
                            code: apiError.code ?? "video_generation_error",
                            message: apiError.message
                        )
                    }

                    guard let requestID = startResponse.resolvedID, !requestID.isEmpty else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8 data)"
                        throw LLMError.decodingError(
                            message: "xAI video generation did not return a request ID. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: requestID))

                    // 2. Poll until done or expired
                    let pollIntervalNanoseconds: UInt64 = 3_000_000_000 // 3 seconds
                    let maxAttempts = 200 // ~10 minutes at 3s intervals
                    var firstPollSnapshot: String?
                    var lastPollSnapshot: String?
                    var consecutiveDecodeFailures = 0
                    let maxConsecutiveDecodeFailures = 5

                    for attempt in 0..<maxAttempts {
                        try Task.checkCancellation()

                        if attempt > 0 {
                            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                        }

                        var pollRequest = URLRequest(url: try validatedURL("\(baseURL)/videos/\(requestID)"))
                        pollRequest.httpMethod = "GET"
                        pollRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                        // Use sendRawRequest so non-2xx responses (e.g. 404 expired, 500 failed)
                        // are handled by resolveVideoStatus instead of throwing.
                        let (pollData, pollHTTPResponse) = try await networkManager.sendRawRequest(pollRequest)
                        let rawBody = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                        let snapshot = "HTTP \(pollHTTPResponse.statusCode): \(String(rawBody.prefix(800)))"
                        lastPollSnapshot = snapshot
                        if firstPollSnapshot == nil { firstPollSnapshot = snapshot }

                        // Try Codable decoding first
                        let statusResponse = try? decoder.decode(XAIVideoStatusResponse.self, from: pollData)

                        // Check for API errors
                        if let apiError = statusResponse?.error {
                            throw LLMError.providerError(
                                code: apiError.code ?? "video_poll_error",
                                message: apiError.message
                            )
                        }

                        // Also parse raw JSON for fallback field inspection
                        let rawJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any]

                        // Resolve status from multiple sources
                        let status = resolveVideoStatus(
                            codable: statusResponse,
                            rawJSON: rawJSON,
                            httpStatus: pollHTTPResponse.statusCode
                        )

                        switch status {
                        case .done:
                            // Terminal — reset counter, extract video.
                            consecutiveDecodeFailures = 0
                            guard let videoURL = extractVideoURL(codable: statusResponse, rawJSON: rawJSON) else {
                                throw LLMError.decodingError(
                                    message: "xAI video generation completed but no video URL found. Response: \(String(rawBody.prefix(500)))"
                                )
                            }

                            let (localURL, mimeType) = try await downloadVideoToLocal(from: videoURL)
                            let video = VideoContent(mimeType: mimeType, data: nil, url: localURL)
                            continuation.yield(.contentDelta(.video(video)))
                            continuation.yield(.messageEnd(usage: nil))
                            continuation.finish()
                            return

                        case .expired:
                            throw LLMError.providerError(
                                code: "video_generation_expired",
                                message: "Video generation request expired before completing."
                            )

                        case .failed(let message):
                            throw LLMError.providerError(
                                code: "video_generation_failed",
                                message: message ?? "Video generation failed on the server."
                            )

                        case .pending:
                            // Only count decode failures for polls that resolved
                            // to .pending via the default fallback (no real signal).
                            // If Codable decoded fine or rawJSON had a status/state
                            // key, the response format is healthy.
                            if statusResponse == nil
                                && pollHTTPResponse.statusCode >= 200
                                && pollHTTPResponse.statusCode < 300 {
                                let rawHasStatusSignal: Bool = {
                                    guard let json = rawJSON else { return false }
                                    for key in ["status", "state"] {
                                        if json[key] is String { return true }
                                    }
                                    return false
                                }()
                                if !rawHasStatusSignal {
                                    consecutiveDecodeFailures += 1
                                    if consecutiveDecodeFailures >= maxConsecutiveDecodeFailures {
                                        throw LLMError.decodingError(
                                            message: "xAI video poll response could not be decoded after \(maxConsecutiveDecodeFailures) consecutive attempts. Last response: \(String(rawBody.prefix(500)))"
                                        )
                                    }
                                } else {
                                    consecutiveDecodeFailures = 0
                                }
                            } else {
                                consecutiveDecodeFailures = 0
                            }
                            continue
                        }
                    }

                    throw LLMError.providerError(
                        code: "video_generation_timeout",
                        message: "Video generation timed out after polling for ~10 minutes.\n\nFirst poll: \(firstPollSnapshot ?? "nil")\n\nLast poll: \(lastPollSnapshot ?? "nil")"
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

    // MARK: - Video Poll Response Helpers

    private enum VideoPollStatus {
        case pending
        case done
        case expired
        case failed(String?)
    }

    /// Resolve poll status from Codable model, raw JSON, and HTTP status code.
    private func resolveVideoStatus(
        codable: XAIVideoStatusResponse?,
        rawJSON: [String: Any]?,
        httpStatus: Int
    ) -> VideoPollStatus {
        // 1. Check Codable status field
        if let status = codable?.status?.lowercased(),
           let resolved = classifyVideoStatusString(status) {
            return resolved
        }

        // 2. Check raw JSON for status/state fields
        if let json = rawJSON {
            for key in ["status", "state"] {
                if let val = json[key] as? String,
                   let resolved = classifyVideoStatusString(val.lowercased(), failureMessage: extractFailureMessage(from: json)) {
                    return resolved
                }
            }

            // 3. If a video URL exists anywhere in the response, treat as done
            if extractVideoURL(codable: codable, rawJSON: rawJSON) != nil {
                return .done
            }
        }

        // 4. Use HTTP status code as a signal for non-2xx responses
        if httpStatus == 404 || httpStatus == 410 {
            return .expired
        }
        if httpStatus >= 500 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "Server error (HTTP \(httpStatus))")
        }
        if httpStatus >= 400 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "HTTP \(httpStatus)")
        }

        // 5. Default to pending
        return .pending
    }

    /// Map a lowercased status string to a VideoPollStatus, returning nil if unrecognized.
    private func classifyVideoStatusString(_ status: String, failureMessage: String? = nil) -> VideoPollStatus? {
        switch status {
        case "done", "complete", "completed", "success":
            return .done
        case "expired":
            return .expired
        case "failed", "error":
            return .failed(failureMessage)
        case "pending", "in_progress", "processing", "queued":
            return .pending
        default:
            return nil
        }
    }

    private func extractFailureMessage(from json: [String: Any]?) -> String? {
        guard let json else { return nil }

        if let message = nonEmptyMessage(json["message"]) {
            return message
        }
        if let errorText = nonEmptyMessage(json["error"]) {
            return errorText
        }

        if let errorObject = json["error"] as? [String: Any] {
            if let message = nonEmptyMessage(errorObject["message"]) {
                return message
            }
            if let detail = nonEmptyMessage(errorObject["detail"]) {
                return detail
            }
            if let reason = nonEmptyMessage(errorObject["reason"]) {
                return reason
            }
        }

        if let errors = json["errors"] as? [[String: Any]] {
            for item in errors {
                if let nested = extractFailureMessage(from: item) {
                    return nested
                }
            }
        }

        for nestedKey in ["response", "data", "result"] {
            if let nested = extractFailureMessage(from: json[nestedKey] as? [String: Any]) {
                return nested
            }
        }

        return nil
    }

    private func nonEmptyMessage(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Extract video URL from multiple possible locations in the response.
    private func extractVideoURL(codable: XAIVideoStatusResponse?, rawJSON: [String: Any]?) -> URL? {
        // Codable path: video.url or result.url
        if let urlString = codable?.resolvedVideo?.url, let url = URL(string: urlString) {
            return url
        }

        guard let json = rawJSON else { return nil }

        // {"video": {"url": "..."}}
        if let video = json["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // {"response": {"video": {"url": "..."}}} (SDK-style nested response)
        if let response = json["response"] as? [String: Any],
           let video = response["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // {"result": {"video": {"url": "..."}}}
        if let result = json["result"] as? [String: Any] {
            if let video = result["video"] as? [String: Any],
               let urlString = video["url"] as? String,
               let url = URL(string: urlString) {
                return url
            }
            if let urlString = result["url"] as? String, let url = URL(string: urlString) {
                return url
            }
        }

        // {"data": {"video": {"url": "..."}}}
        if let data = json["data"] as? [String: Any],
           let video = data["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // {"url": "..."} at top level (only if it looks like a video URL)
        if let urlString = json["url"] as? String,
           let url = URL(string: urlString),
           urlString.contains("video") || urlString.contains(".mp4") || urlString.contains("vidgen") {
            return url
        }

        return nil
    }

    private func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        videoURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let isVideoEdit = videoURL?.isEmpty == false
        let endpoint = isVideoEdit ? "videos/edits" : "videos/generations"

        var request = URLRequest(url: try validatedURL("\(baseURL)/\(endpoint)"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let videoControls = controls.xaiVideoGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        // xAI docs: duration/aspect_ratio/resolution are unsupported for video editing.
        if !isVideoEdit {
            if let duration = videoControls?.duration {
                body["duration"] = min(max(duration, 1), 15)
            }
            if let aspectRatio = videoControls?.aspectRatio {
                let supportedVideoRatios: Set<XAIAspectRatio> = [
                    .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3
                ]
                if supportedVideoRatios.contains(aspectRatio) {
                    body["aspect_ratio"] = aspectRatio.rawValue
                }
            }
            if let resolution = videoControls?.resolution {
                body["resolution"] = resolution.rawValue
            }
        }

        if let videoURL, !videoURL.isEmpty {
            body["video"] = ["url": videoURL]
        } else if let imageURL, !imageURL.isEmpty {
            body["image"] = ["url": imageURL]
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func downloadVideoToLocal(from url: URL) async throws -> (URL, String) {
        let result = try await VideoAttachmentUtility.downloadToLocal(
            from: url,
            networkManager: networkManager
        )
        return (result.localURL, result.mimeType)
    }

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let endpoint = (imageURL?.isEmpty == false) ? "images/edits" : "images/generations"

        var request = URLRequest(url: try validatedURL("\(baseURL)/\(endpoint)"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let imageControls = controls.xaiImageGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }
        if let imageURL, !imageURL.isEmpty {
            body["image_url"] = imageURL
        }

        // xAI currently uses `aspect_ratio`; map older persisted `size` values for compatibility.
        if let aspectRatio = imageControls?.aspectRatio ?? imageControls?.size?.mappedAspectRatio {
            body["aspect_ratio"] = aspectRatio.rawValue
        }

        body["response_format"] = "b64_json"
        if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            body["user"] = user
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Capability/model inference

    private func inferCapabilities(for model: XAIModelData) -> ModelCapability {
        let lowerID = model.id.lowercased()

        let inputModalities = Set((model.inputModalities ?? []).map { $0.lowercased() })
        let outputModalities = Set((model.outputModalities ?? []).map { $0.lowercased() })
        let allModalities = Set((model.modalities ?? []).map { $0.lowercased() })

        let hasVideoOutput = outputModalities.contains(where: { $0.contains("video") })
            || allModalities.contains(where: { $0.contains("video") })
        let videoModel = hasVideoOutput || isVideoGenerationModelID(lowerID)

        if videoModel {
            return [.videoGeneration]
        }

        let hasImageOutput = outputModalities.contains(where: { $0.contains("image") })
            || allModalities.contains(where: { $0.contains("image") })
        let imageModel = hasImageOutput || isImageGenerationModelID(lowerID)

        if imageModel {
            return [.imageGeneration]
        }

        var caps: ModelCapability = [.streaming, .toolCalling, .promptCaching]

        if inputModalities.contains(where: { $0.contains("image") }) || outputModalities.contains(where: { $0.contains("image") }) {
            caps.insert(.vision)
        }

        if Self.chatReasoningModelIDs.contains(lowerID) {
            caps.insert(.vision)
            caps.insert(.reasoning)
        }

        if supportsNativePDF(model.id) {
            caps.insert(.nativePDF)
        }

        return caps
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return isImageGenerationModelID(modelID.lowercased())
    }

    private func isImageGenerationModelID(_ lowerModelID: String) -> Bool {
        Self.imageGenerationModelIDs.contains(lowerModelID)
    }

    private func isVideoGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.videoGeneration) == true {
            return true
        }
        return isVideoGenerationModelID(modelID.lowercased())
    }

    private func isVideoGenerationModelID(_ lowerModelID: String) -> Bool {
        Self.videoGenerationModelIDs.contains(lowerModelID)
    }

    // MARK: - Shared helpers

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    private func supportsReasoningEffort(modelID: String) -> Bool {
        Self.reasoningEffortModelIDs.contains(modelID.lowercased())
    }

    private func supportsWebSearch(modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: .xai, modelID: modelID)
    }

    private enum MediaEditMode {
        case none
        case image
        case video
    }

    private func mediaPrompt(from messages: [Message], mode: MediaEditMode) throws -> String {
        let userPrompts = userTextPrompts(from: messages)
        guard let latest = userPrompts.last else {
            throw LLMError.invalidRequest(message: "xAI media generation requires a text prompt.")
        }

        guard mode != .none else {
            return latest
        }

        let recentPrompts = Array(userPrompts.suffix(6))
        let originalPrompt = recentPrompts.first ?? latest
        let latestPrompt = recentPrompts.last ?? latest
        let priorEdits = Array(recentPrompts.dropFirst().dropLast())

        if mode == .image, userPrompts.count < 2 {
            return latest
        }

        if mode == .image,
           priorEdits.isEmpty,
           originalPrompt.caseInsensitiveCompare(latestPrompt) == .orderedSame {
            return latest
        }

        let continuityInstruction: String = switch mode {
        case .image:
            "Keep the main subject, composition, and scene continuity unless explicitly changed."
        case .video:
            "Keep the main subject, composition, camera motion, and timing continuity unless explicitly changed."
        case .none:
            ""
        }

        let mediaLabel: String = switch mode {
        case .image: "image"
        case .video: "video"
        case .none: "media"
        }

        var lines: [String] = [
            "Edit the provided input \(mediaLabel).",
            continuityInstruction,
            "",
            "Original request:",
            originalPrompt
        ]

        if !priorEdits.isEmpty {
            lines.append("")
            lines.append("Edits already applied:")
            for (idx, edit) in priorEdits.enumerated() {
                lines.append("\(idx + 1). \(edit)")
            }
        }

        lines.append("")
        lines.append("Apply this new edit now:")
        lines.append(latestPrompt)

        return lines.joined(separator: "\n")
    }

    private func userTextPrompts(from messages: [Message]) -> [String] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }

            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            return text.isEmpty ? nil : text
        }
    }

    private func imageURLForImageGeneration(from messages: [Message]) -> String? {
        // If the latest user turn includes an image, prefer that explicit input.
        if let latestUserImageURL = latestUserImageURL(from: messages) {
            return latestUserImageURL
        }

        // Otherwise, continue editing from the latest assistant-generated image.
        if let assistantImageURL = firstImageURLString(from: messages, roles: [.assistant]) {
            return assistantImageURL
        }

        // Finally, fall back to any older user-provided image in history.
        return firstImageURLString(from: messages, roles: [.user])
    }

    private func latestUserImageURL(from messages: [Message]) -> String? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstImageURLString(in: latestUserMessage)
    }

    private func firstImageURLString(in message: Message) -> String? {
        for part in message.content {
            if case .image(let image) = part,
               let urlString = imageURLString(image) {
                return urlString
            }
        }
        return nil
    }

    private func firstImageURLString(from messages: [Message], roles: [MessageRole]) -> String? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let urlString = firstImageURLString(in: message) {
                return urlString
            }
        }
        return nil
    }

    private func videoInputForVideoGeneration(from messages: [Message]) -> VideoContent? {
        // If the latest user turn includes a video, prefer that explicit input.
        if let latestUserVideo = latestUserVideoInput(from: messages) {
            return latestUserVideo
        }

        // If the latest user prompt includes a remote video URL, use that as input.
        if let latestUserRemoteVideo = latestUserMentionedRemoteVideoInput(from: messages) {
            return latestUserRemoteVideo
        }

        // Otherwise, continue editing from the latest assistant-generated video.
        if let assistantVideo = firstVideoInput(from: messages, roles: [.assistant]) {
            return assistantVideo
        }

        // Then fall back to any older user-provided video attachment in history.
        if let olderUserVideo = firstVideoInput(from: messages, roles: [.user]) {
            return olderUserVideo
        }

        // Finally, fall back to any older user prompt that included a remote video URL.
        return firstMentionedRemoteVideoInput(from: messages, roles: [.user])
    }

    private func latestUserVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstVideoInput(in: latestUserMessage)
    }

    private func firstVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            if case .video(let video) = part {
                return video
            }
        }
        return nil
    }

    private func firstVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private func latestUserMentionedRemoteVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstMentionedRemoteVideoInput(in: latestUserMessage)
    }

    private func firstMentionedRemoteVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstMentionedRemoteVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private func firstMentionedRemoteVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            guard case .text(let text) = part,
                  let url = firstRemoteVideoURLMention(in: text) else {
                continue
            }

            let inferred = VideoAttachmentUtility.resolveVideoFormat(contentType: nil, url: url)
            return VideoContent(mimeType: inferred.mimeType, data: nil, url: url)
        }
        return nil
    }

    private func firstRemoteVideoURLMention(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let url = match.url,
                  isHTTPRemoteURL(url),
                  looksLikeVideoRemoteURL(url) else {
                continue
            }
            return url
        }

        return nil
    }

    private func resolvedVideoURL(for video: VideoContent?) async throws -> String? {
        guard let video else { return nil }

        if let remote = remoteVideoURLString(video) {
            return remote
        }

        let r2PluginEnabled = await r2Uploader.isPluginEnabled()
        guard r2PluginEnabled else {
            throw LLMError.invalidRequest(
                message: "xAI local video input requires Cloudflare R2 Upload. Enable Settings → Plugins → Cloudflare R2 Upload and configure it, or attach a public HTTPS video URL."
            )
        }

        do {
            let uploadedURL = try await r2Uploader.uploadVideo(video)
            return uploadedURL.absoluteString
        } catch let error as CloudflareR2UploaderError {
            throw LLMError.invalidRequest(
                message: "\(error.localizedDescription)\n\nOpen Settings → Plugins → Cloudflare R2 Upload to complete the configuration."
            )
        } catch {
            throw error
        }
    }

    private func remoteVideoURLString(_ video: VideoContent) -> String? {
        guard let url = video.url, isHTTPRemoteURL(url) else {
            return nil
        }
        return url.absoluteString
    }

    private func isHTTPRemoteURL(_ url: URL) -> Bool {
        guard !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    private func looksLikeVideoRemoteURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let knownVideoExtensions: Set<String> = [
            "mp4", "m4v", "mov", "webm", "avi", "mkv",
            "mpeg", "mpg", "wmv", "flv", "3gp", "3gpp"
        ]
        if knownVideoExtensions.contains(ext) {
            return true
        }

        let lower = url.absoluteString.lowercased()
        let markers = [
            ".mp4", ".m4v", ".mov", ".webm", ".avi", ".mkv",
            ".mpeg", ".mpg", ".wmv", ".flv", ".3gp", ".3gpp",
            "/video", "-video", "_video", "video="
        ]
        return markers.contains { lower.contains($0) }
    }

    private func imageURLString(_ image: ImageContent) -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }

        if let url = image.url {
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }

        return nil
    }

    private func resolveImageOutputs(from items: [XAIMediaItem]) -> [ImageContent] {
        var out: [ImageContent] = []
        out.reserveCapacity(items.count)

        for item in items {
            if let b64 = item.b64JSON,
               let data = Data(base64Encoded: b64) {
                out.append(ImageContent(mimeType: item.mimeType ?? "image/png", data: data, url: nil))
                continue
            }

            if let rawURL = item.resolvedURL,
               let url = URL(string: rawURL) {
                let mime = item.mimeType ?? inferImageMIMEType(from: url) ?? "image/png"
                out.append(ImageContent(mimeType: mime, data: nil, url: url))
            }
        }

        return out
    }

    private func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }

    private func applyProviderSpecificOverrides(controls: GenerationControls, body: inout [String: Any]) {
        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }
    }

    private func translateInput(_ messages: [Message], supportsNativePDF: Bool) -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
                    }
                }

            case .system, .user, .assistant:
                if let translated = translateMessage(message, supportsNativePDF: supportsNativePDF) {
                    items.append(translated)
                }

                if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    items.append(contentsOf: translateFunctionCalls(toolCalls))
                }

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
                    }
                }
            }
        }

        return items
    }

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any]? {
        let content = message.content.compactMap { translateContentPart($0, supportsNativePDF: supportsNativePDF) }

        guard !content.isEmpty else { return nil }

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    private func translateFunctionCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map { call in
            [
                "type": "function_call",
                "call_id": call.id,
                "name": call.name,
                "arguments": encodeJSONObject(call.arguments)
            ]
        }
    }

    private func sanitizedToolOutput(_ raw: String, toolName: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        if let toolName, !toolName.isEmpty {
            return "Tool \(toolName) returned no output"
        }
        return "Tool returned no output"
    }

    private func translateContentPart(_ part: ContentPart, supportsNativePDF: Bool) -> [String: Any]? {
        switch part {
        case .text(let text):
            return [
                "type": "input_text",
                "text": text
            ]

        case .image(let image):
            if let data = image.data {
                return [
                    "type": "input_image",
                    "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                ]
            }
            if let url = image.url {
                if url.isFileURL, let data = try? Data(contentsOf: url) {
                    return [
                        "type": "input_image",
                        "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                    ]
                }
                return [
                    "type": "input_image",
                    "image_url": url.absoluteString
                ]
            }
            return nil

        case .file(let file):
            if supportsNativePDF && file.mimeType == "application/pdf" {
                let pdfData: Data?
                if let data = file.data {
                    pdfData = data
                } else if let url = file.url, url.isFileURL {
                    pdfData = try? Data(contentsOf: url)
                } else {
                    pdfData = nil
                }

                if let pdfData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:application/pdf;base64,\(pdfData.base64EncodedString())"
                    ]
                }
            }

            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": "input_text",
                "text": text
            ]

        case .video(let video):
            return [
                "type": "input_text",
                "text": unsupportedVideoInputNotice(video, providerName: "xAI")
            ]

        case .thinking, .redactedThinking, .audio:
            return nil
        }
    }

    private func unsupportedVideoInputNotice(_ video: VideoContent, providerName: String) -> String {
        let detail: String
        if let url = video.url {
            detail = url.isFileURL ? url.lastPathComponent : url.absoluteString
        } else if let data = video.data {
            detail = "\(data.count) bytes"
        } else {
            detail = "no media payload"
        }
        return "Video attachment omitted (\(video.mimeType), \(detail)): \(providerName) chat API does not support native video input in Jin yet."
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

    private func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: ResponsesAPIFunctionCallState]
    ) throws -> StreamEvent? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponsesAPICreatedEvent.self, from: jsonData)
            return .messageStart(id: event.response.id)

        case "response.output_text.delta":
            let event = try decoder.decode(ResponsesAPIOutputTextDeltaEvent.self, from: jsonData)
            return .contentDelta(.text(event.delta))

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.output_item.added":
            let event = try decoder.decode(ResponsesAPIOutputItemAddedEvent.self, from: jsonData)
            guard event.item.type == "function_call",
                  let itemID = event.item.id,
                  let callID = event.item.callId,
                  let name = event.item.name else {
                return nil
            }

            functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
            return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }

            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return .toolCallDelta(id: state.callID, argumentsDelta: event.delta)

        case "response.function_call_arguments.done":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }
            functionCallsByItemID.removeValue(forKey: event.itemId)

            let args = parseJSONObject(event.arguments)
            return .toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))

        case "response.completed":
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            return .messageEnd(usage: event.response.toUsage())

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponsesAPIFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return .error(.providerError(code: errorEvent.response.error?.code ?? "response_failed", message: message))
            }
            return .error(.providerError(code: "response_failed", message: data))

        default:
            return nil
        }
    }

    private struct CitationSourceCandidate {
        let url: String
        let title: String?
        let snippet: String?
    }

    private func citationSearchActivity(sources: [CitationSourceCandidate]?, responseID: String) -> SearchActivity? {
        citationSearchActivity(sources: sources, responseID: Optional(responseID))
    }

    private func citationCandidates(
        citations: [String]?,
        output: [ResponsesAPIOutputItem]?,
        fallbackText: String?
    ) -> [CitationSourceCandidate]? {
        let inlineCandidates = inlineCitationCandidates(from: output)
        if !inlineCandidates.isEmpty {
            return inlineCandidates
        }

        if let citations, !citations.isEmpty {
            let normalized = normalizedCitationCandidates(fromURLs: citations)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard let fallbackText, !fallbackText.isEmpty else {
            return nil
        }

        let urls = markdownCitationURLs(from: fallbackText)
        let normalized = normalizedCitationCandidates(fromURLs: urls)
        return normalized.isEmpty ? nil : normalized
    }

    private func inlineCitationCandidates(from output: [ResponsesAPIOutputItem]?) -> [CitationSourceCandidate] {
        guard let output else { return [] }

        var ordered: [CitationSourceCandidate] = []
        var indexByURLKey: [String: Int] = [:]

        for item in output where item.type == "message" {
            for content in item.content ?? [] where content.type == "output_text" {
                for annotation in content.annotations ?? [] where annotation.type == "url_citation" {
                    guard let rawURL = annotation.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawURL.isEmpty,
                          let url = URL(string: rawURL),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else {
                        continue
                    }

                    let canonical = url.absoluteString
                    let key = canonical.lowercased()
                    let title = normalizedCitationTitle(annotation.title)
                    let snippet = citationPreviewSnippet(
                        text: content.text,
                        startIndex: annotation.startIndex,
                        endIndex: annotation.endIndex
                    )

                    if let existingIndex = indexByURLKey[key] {
                        let existing = ordered[existingIndex]
                        ordered[existingIndex] = CitationSourceCandidate(
                            url: existing.url,
                            title: existing.title ?? title,
                            snippet: preferredSnippet(existing: existing.snippet, candidate: snippet)
                        )
                        continue
                    }

                    indexByURLKey[key] = ordered.count
                    ordered.append(
                        CitationSourceCandidate(
                            url: canonical,
                            title: title,
                            snippet: snippet
                        )
                    )
                }
            }
        }

        return ordered
    }

    private func normalizedCitationCandidates(fromURLs urls: [String]) -> [CitationSourceCandidate] {
        guard !urls.isEmpty else { return [] }

        var seen: Set<String> = []
        var out: [CitationSourceCandidate] = []
        out.reserveCapacity(urls.count)

        for raw in urls {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            let canonical = url.absoluteString
            let dedupeKey = canonical.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            out.append(
                CitationSourceCandidate(
                    url: canonical,
                    title: nil,
                    snippet: nil
                )
            )
        }

        return out
    }

    private func markdownCitationURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"\[\[\d+\]\]\((https?://[^)\s]+)\)|\[\d+\]\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [String] = []
        urls.reserveCapacity(4)

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }

            for group in [1, 2] {
                let groupRange = match.range(at: group)
                guard groupRange.location != NSNotFound,
                      let swiftRange = Range(groupRange, in: text) else {
                    continue
                }
                urls.append(String(text[swiftRange]))
                break
            }
        }

        return urls
    }

    private func citationSearchActivity(sources: [CitationSourceCandidate]?, responseID: String?) -> SearchActivity? {
        guard let sources, !sources.isEmpty else { return nil }

        let payloads: [[String: Any]] = sources.map { source in
            var payload: [String: Any] = [
                "type": "url_citation",
                "url": source.url
            ]
            if let title = source.title {
                payload["title"] = title
            }
            if let snippet = source.snippet {
                payload["snippet"] = snippet
            }
            return payload
        }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(payloads)
        ]
        if let first = sources.first {
            arguments["url"] = AnyCodable(first.url)
            if let title = first.title {
                arguments["title"] = AnyCodable(title)
            }
        }

        return SearchActivity(
            id: "\(responseID ?? UUID().uuidString):citations",
            type: "url_citation",
            status: .completed,
            arguments: arguments
        )
    }

    private func normalizedCitationTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        return trimmed
    }

    private func preferredSnippet(existing: String?, candidate: String?) -> String? {
        guard let candidate else { return existing }
        guard let existing else { return candidate }
        return candidate.count > existing.count ? candidate : existing
    }
}

// Response types are defined in XAIAdapterResponseTypes.swift
