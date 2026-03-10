import Foundation

/// xAI provider adapter.
///
/// - Chat models use the Responses API (`/responses`).
/// - Image models use `/images/generations` + `/images/edits`.
/// - Video models use `/videos/generations` (text/image) and `/videos/edits` (video edit), both async.
///
/// Media helpers are in `XAIMediaHelpers.swift`.
/// Video generation is in `XAIVideoGeneration.swift`.
/// Citation resolution is in `XAICitationResolver.swift`.
/// Response types are in `XAIAdapterResponseTypes.swift`.
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
    static let imageGenerationModelIDs: Set<String> = [
        "grok-imagine-image",
        "grok-imagine-image-pro",
        "grok-2-image-1212",
    ]
    static let videoGenerationModelIDs: Set<String> = [
        "grok-imagine-video",
    ]
    private static let reasoningEffortModelIDs: Set<String> = [
        "grok-3-mini",
    ]

    let networkManager: NetworkManager
    let r2Uploader: CloudflareR2Uploader
    let apiKey: String

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
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            accept: nil,
            includeUserAgent: false
        )

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

    var baseURL: String {
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

                if let notice = response.incompleteNoticeMarkdown {
                    continuation.yield(.contentDelta(.text(notice)))
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
                    var didEmitTerminalMessageEnd = false

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if type == "response.incomplete",
                               let jsonData = data.data(using: .utf8),
                               let incomplete = try? streamDecoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) {
                                if let notice = incomplete.response.incompleteNoticeMarkdown {
                                    continuation.yield(.contentDelta(.text(notice)))
                                }
                                continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
                                didEmitTerminalMessageEnd = true
                                continue
                            }

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
                                if case .messageEnd = streamEvent {
                                    didEmitTerminalMessageEnd = true
                                }
                                continuation.yield(streamEvent)
                            }
                        case .done:
                            if !didEmitTerminalMessageEnd {
                                continuation.yield(.messageEnd(usage: nil))
                            }
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
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)
        let conversationID = normalizedTrimmedString(controls.contextCache?.conversationID)

        var body: [String: Any] = [
            "model": modelID,
            "input": try translateInput(messages, supportsNativePDF: nativePDFEnabled),
            "stream": streaming
        ]

        if controls.contextCache?.mode != .off {
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

        var additionalHeaders: [String: String] = [:]
        if controls.contextCache?.mode != .off, let conversationID {
            additionalHeaders["x-grok-conv-id"] = conversationID
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/responses"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            additionalHeaders: additionalHeaders,
            includeUserAgent: false
        )
    }

    // MARK: - Image Generation

    private func makeImageGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let imageURL = try imageURLForImageGeneration(from: messages)
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

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let isImageEdit = imageURL?.isEmpty == false
        let endpoint = isImageEdit ? "images/edits" : "images/generations"

        let imageControls = controls.xaiImageGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }
        if let imageURL, !imageURL.isEmpty {
            body["image"] = ["url": imageURL]
        }

        if !isImageEdit,
           let aspectRatio = imageControls?.aspectRatio ?? imageControls?.size?.mappedAspectRatio {
            body["aspect_ratio"] = aspectRatio.rawValue
        }

        body["response_format"] = "b64_json"
        if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            body["user"] = user
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/\(endpoint)"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    // MARK: - Capability / Model Inference

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

    func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return isImageGenerationModelID(modelID.lowercased())
    }

    func isImageGenerationModelID(_ lowerModelID: String) -> Bool {
        Self.imageGenerationModelIDs.contains(lowerModelID)
    }

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.videoGeneration) == true {
            return true
        }
        return isVideoGenerationModelID(modelID.lowercased())
    }

    func isVideoGenerationModelID(_ lowerModelID: String) -> Bool {
        Self.videoGenerationModelIDs.contains(lowerModelID)
    }

    // MARK: - Shared Helpers

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

    func applyProviderSpecificOverrides(controls: GenerationControls, body: inout [String: Any]) {
        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }
    }

    // MARK: - Input Translation

    private func translateInput(_ messages: [Message], supportsNativePDF: Bool) throws -> [[String: Any]] {
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
                if let translated = try translateMessage(message, supportsNativePDF: supportsNativePDF) {
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

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try translateContentPart(part, supportsNativePDF: supportsNativePDF) {
                content.append(translated)
            }
        }

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

    private func translateContentPart(_ part: ContentPart, supportsNativePDF: Bool) throws -> [String: Any]? {
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
                if url.isFileURL {
                    let data = try resolveFileData(from: url)
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
                    pdfData = try resolveFileData(from: url)
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

    // MARK: - SSE Parsing

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
}
