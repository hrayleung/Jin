import Foundation

private func normalizedSearchPreviewText(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let collapsed = raw
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty else { return nil }
    if collapsed.count <= 420 {
        return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 420)
    return String(collapsed[..<endIndex]) + "…"
}

private func citationPreviewSnippet(
    text: String?,
    startIndex: Int?,
    endIndex: Int?
) -> String? {
    guard let text, !text.isEmpty else { return nil }
    guard let startIndex, let endIndex,
          startIndex >= 0, endIndex > startIndex else {
        return nil
    }

    let nsText = text as NSString
    let textLength = nsText.length
    guard startIndex < textLength else { return nil }

    let clampedEnd = min(endIndex, textLength)
    guard clampedEnd > startIndex else { return nil }

    let contextRadius = 80
    let windowStart = max(0, startIndex - contextRadius)
    let windowEnd = min(textLength, clampedEnd + contextRadius)
    guard windowEnd > windowStart else { return nil }

    let snippet = nsText.substring(with: NSRange(location: windowStart, length: windowEnd - windowStart))
    return normalizedSearchPreviewText(snippet)
}

/// OpenAI provider adapter (Responses API WebSocket mode)
actor OpenAIWebSocketAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching]

    private let networkManager: NetworkManager
    private let apiKey: String
    private let urlSession: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var isResponseInFlight = false
    private var previousResponseID: String?

    nonisolated static func responseCreateEvent(from responsePayload: [String: Any]) -> [String: Any] {
        var event = responsePayload
        event["type"] = "response.create"
        return event
    }

    nonisolated static func decodeErrorEventPayload(_ jsonData: Data, fallbackMessage: String) -> LLMError {
        let payload = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
        let error = payload?["error"] as? [String: Any]
        let code = (error?["code"] as? String)
            ?? (error?["type"] as? String)
            ?? "error"
        let message = (error?["message"] as? String)
            ?? (payload?["message"] as? String)
            ?? fallbackMessage
        return .providerError(code: code, message: message)
    }

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager(),
        urlSession: URLSession = .shared
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.urlSession = urlSession
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming _: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // OpenAI currently documents audio input support primarily on Chat Completions.
        // Route audio-bearing requests through the OpenAI-compatible Chat Completions path.
        if shouldRouteToChatCompletionsForAudio(messages: messages, modelID: modelID) {
            let chatCompletionsAdapter = OpenAICompatibleAdapter(
                providerConfig: ProviderConfig(
                    id: providerConfig.id,
                    name: providerConfig.name,
                    type: .openaiCompatible,
                    iconID: providerConfig.iconID,
                    authModeHint: providerConfig.authModeHint,
                    apiKey: providerConfig.apiKey,
                    serviceAccountJSON: providerConfig.serviceAccountJSON,
                    baseURL: resolvedHTTPBaseURLString(),
                    models: providerConfig.models
                ),
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await chatCompletionsAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: true
            )
        }

        if isResponseInFlight {
            throw LLMError.invalidRequest(message: "OpenAI WebSocket mode does not support concurrent responses on a single connection.")
        }

        let (inputMessages, continuationID) = continuationState(for: messages)
        let responsePayload = try buildResponsePayload(
            messages: inputMessages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            previousResponseID: continuationID
        )

        let createEvent = Self.responseCreateEvent(from: responsePayload)

        let createEventData = try JSONSerialization.data(withJSONObject: createEvent)
        guard let createEventString = String(data: createEventData, encoding: .utf8) else {
            throw LLMError.invalidRequest(message: "Failed to encode WebSocket request payload.")
        }

        let ws = try openWebSocket()
        isResponseInFlight = true

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ws.send(.string(createEventString))

                    var functionCallsByItemID: [String: FunctionCallState] = [:]

                    while true {
                        try Task.checkCancellation()

                        let message = try await ws.receive()
                        let jsonString: String
                        switch message {
                        case .string(let text):
                            jsonString = text
                        case .data(let data):
                            jsonString = String(data: data, encoding: .utf8) ?? ""
                        @unknown default:
                            jsonString = ""
                        }

                        guard let eventType = parseEventType(from: jsonString) else {
                            continue
                        }

                        if let streamEvent = try parseSSEEvent(
                            type: eventType,
                            data: jsonString,
                            functionCallsByItemID: &functionCallsByItemID
                        ) {
                            if case .messageStart(let id) = streamEvent {
                                previousResponseID = id
                            }

                            continuation.yield(streamEvent)
                        }

                        if eventType == "response.completed"
                            || eventType == "response.failed"
                            || eventType == "response.canceled"
                            || eventType == "response.cancelled"
                            || eventType == "error" {
                            break
                        }
                    }

                    isResponseInFlight = false
                    continuation.finish()
                } catch is CancellationError {
                    await cancelResponseIfPossible()
                    resetWebSocketState()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    resetWebSocketState()
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.cancelResponseIfPossible()
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: try validatedURL("\(resolvedHTTPBaseURLString())/models"))
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
        var request = URLRequest(url: try validatedURL("\(resolvedHTTPBaseURLString())/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let reasoningModelIDs: Set<String> = ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11", "o1", "o3", "o4"]
        let visionModelIDs: Set<String> = ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-4o", "o3", "o4"]
        let largeContextModelIDs: Set<String> = ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11"]

        return response.data.map { model in
            let lower = model.id.lowercased()
            var caps: ModelCapability = [.streaming, .toolCalling, .promptCaching]
            var reasoningConfig: ModelReasoningConfig?

            if reasoningModelIDs.contains(lower) {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            if visionModelIDs.contains(lower) {
                caps.insert(.vision)
            }
            if supportsAudioInputModelID(lower) {
                caps.insert(.audio)
            }

            // Use the same exact-ID support matrix as UI model badges.
            if JinModelSupport.supportsNativePDF(providerType: providerConfig.type, modelID: model.id) && caps.contains(.vision) {
                caps.insert(.nativePDF)
            }

            let contextWindow: Int
            if largeContextModelIDs.contains(lower) {
                contextWindow = 400000
            } else {
                contextWindow = 128000
            }

            return ModelInfo(
                id: model.id,
                name: model.id,
                capabilities: caps,
                contextWindow: contextWindow,
                reasoningConfig: reasoningConfig
            )
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private func openWebSocket() throws -> URLSessionWebSocketTask {
        if let existing = webSocketTask, existing.state == .running {
            return existing
        }

        let socketURL = try resolvedWebSocketResponsesURL()
        var request = URLRequest(url: socketURL)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        task.resume()

        webSocketTask = task
        return task
    }

    private func resolvedWebSocketResponsesURL() throws -> URL {
        let raw = (providerConfig.baseURL ?? ProviderType.openaiWebSocket.defaultBaseURL ?? "wss://api.openai.com/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = try validatedURL(raw.isEmpty ? "wss://api.openai.com/v1" : raw)
        let normalized = normalizedOpenAIBaseURL(base)
        let wsBase = try coerceToWebSocketScheme(normalized)

        if wsBase.lastPathComponent == "responses" {
            return wsBase
        }
        return wsBase.appendingPathComponent("responses")
    }

    private func normalizedOpenAIBaseURL(_ url: URL) -> URL {
        if url.lastPathComponent == "responses" {
            return url.deletingLastPathComponent()
        }
        return url
    }

    private func coerceToWebSocketScheme(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LLMError.invalidRequest(message: "Invalid URL: \(url.absoluteString)")
        }

        let scheme = (components.scheme ?? "").lowercased()
        switch scheme {
        case "ws", "wss":
            break
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            throw LLMError.invalidRequest(message: "Invalid WebSocket URL scheme: \(components.scheme ?? "")")
        }

        guard let coerced = components.url else {
            throw LLMError.invalidRequest(message: "Invalid URL: \(url.absoluteString)")
        }
        return coerced
    }

    private func resolvedHTTPBaseURLString() -> String {
        let fallback = ProviderType.openai.defaultBaseURL ?? "https://api.openai.com/v1"
        let raw = (providerConfig.baseURL ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = try? validatedURL(raw.isEmpty ? fallback : raw) else {
            return fallback
        }

        let normalized = normalizedOpenAIBaseURL(url)
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            return fallback
        }

        let scheme = (components.scheme ?? "").lowercased()
        switch scheme {
        case "http", "https":
            break
        case "ws":
            components.scheme = "http"
        case "wss":
            components.scheme = "https"
        default:
            components.scheme = "https"
        }

        return components.url?.absoluteString ?? fallback
    }

    private func cancelResponseIfPossible() async {
        guard isResponseInFlight else { return }
        guard let webSocketTask, webSocketTask.state == .running else { return }

        let cancelEvent: [String: Any] = ["type": "response.cancel"]
        guard let data = try? JSONSerialization.data(withJSONObject: cancelEvent),
              let message = String(data: data, encoding: .utf8) else {
            return
        }

        try? await webSocketTask.send(.string(message))
    }

    private func resetWebSocketState() {
        isResponseInFlight = false
        previousResponseID = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func continuationState(for messages: [Message]) -> (messages: [Message], previousResponseID: String?) {
        guard let previousResponseID else {
            return (messages, nil)
        }

        guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }),
              lastAssistantIndex < messages.count - 1 else {
            return (messages, previousResponseID)
        }

        let suffix = Array(messages.suffix(from: messages.index(after: lastAssistantIndex)))
        return (suffix, previousResponseID)
    }

    private func buildResponsePayload(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        previousResponseID: String?
    ) throws -> [String: Any] {
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "model": modelID,
            "input": translateInput(messages, supportsNativePDF: nativePDFEnabled),
        ]

        if let previousResponseID {
            body["previous_response_id"] = previousResponseID
        }

        if controls.contextCache?.mode != .off {
            if let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) {
                body["prompt_cache_key"] = cacheKey
            }
            if let retention = controls.contextCache?.ttl?.providerTTLString {
                body["prompt_cache_retention"] = retention
            }
        }

        let reasoningEffort = (controls.reasoning?.enabled == true) ? controls.reasoning?.effort : nil
        let reasoningEnabled = (reasoningEffort ?? .none) != .none

        // When reasoning is enabled, the Responses API rejects temperature/top_p.
        if !reasoningEnabled {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }

        if reasoningEnabled, let effort = reasoningEffort {
            var reasoningDict: [String: Any] = [
                "effort": mapReasoningEffort(effort, modelID: modelID)
            ]

            // Add summary control if specified
            if let summary = controls.reasoning?.summary {
                reasoningDict["summary"] = summary.rawValue
            }

            body["reasoning"] = reasoningDict
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            var webSearchTool: [String: Any] = ["type": "web_search"]
            if let contextSize = controls.webSearch?.contextSize {
                webSearchTool["search_context_size"] = contextSize.rawValue
            }
            toolObjects.append(webSearchTool)
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        for (key, value) in controls.providerSpecific {
            guard key != "prompt_cache_min_tokens" else {
                continue
            }
            body[key] = value.value
        }

        // Ask Responses API to include source URLs/titles for web_search_call actions when possible.
        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            body["include"] = mergedIncludeFields(body["include"], adding: "web_search_call.action.sources")
        }

        return body
    }

    private func mergedIncludeFields(_ existing: Any?, adding field: String) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        if let existingStrings = existing as? [String] {
            for item in existingStrings {
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                out.append(trimmed)
            }
        } else if let existingAny = existing as? [Any] {
            for item in existingAny {
                guard let value = item as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                out.append(trimmed)
            }
        }

        let target = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty, !seen.contains(target) {
            out.append(target)
        }

        return out
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: providerConfig.type,
            modelID: modelID
        )

        switch normalized {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        }
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: providerConfig.type, modelID: modelID)
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
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

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        let audioInputModelIDs: Set<String> = [
            "gpt-4o-audio-preview",
            "gpt-4o-audio-preview-2024-10-01",
            "gpt-4o-mini-audio-preview",
            "gpt-4o-mini-audio-preview-2024-12-17",
            "gpt-4o-realtime-preview",
            "gpt-4o-realtime-preview-2024-10-01",
            "gpt-4o-realtime-preview-2024-12-17",
            "gpt-4o-mini-realtime-preview",
            "gpt-4o-mini-realtime-preview-2024-12-17",
            "gpt-realtime",
            "gpt-realtime-mini",
        ]
        return audioInputModelIDs.contains(lowerModelID)
    }

    private func shouldRouteToChatCompletionsForAudio(messages: [Message], modelID: String) -> Bool {
        guard supportsAudioInputModelID(modelID.lowercased()) else {
            return false
        }

        for message in messages where message.role != .tool {
            if message.content.contains(where: { part in
                if case .audio = part { return true }
                return false
            }) {
                return true
            }
        }

        return false
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
        let content = message.content.compactMap { part in
            translateContentPart(part, role: message.role, supportsNativePDF: supportsNativePDF)
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

    private func translateContentPart(_ part: ContentPart, role: MessageRole, supportsNativePDF: Bool) -> [String: Any]? {
        switch part {
        case .text(let text):
            // OpenAI Responses API: assistant uses output_text, others use input_text
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
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
            // Native PDF support for GPT-5.2+, o3+, o4+
            if supportsNativePDF && file.mimeType == "application/pdf" {
                // Load PDF data from file URL or use existing data
                let pdfData: Data?
                if let data = file.data {
                    pdfData = data
                } else if let url = file.url, url.isFileURL {
                    pdfData = try? Data(contentsOf: url)
                } else {
                    pdfData = nil
                }

                if let pdfData = pdfData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:application/pdf;base64,\(pdfData.base64EncodedString())"
                    ]
                }
            }

            // Fallback to text extraction for non-PDF or unsupported models
            let textType = (role == .assistant) ? "output_text" : "input_text"
            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": textType,
                "text": text
            ]

        case .video(let video):
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
                "text": unsupportedVideoInputNotice(video, providerName: "OpenAI")
            ]

        case .audio(let audio):
            guard role == .user else { return nil }
            return openAIInputAudioPart(audio)

        case .thinking, .redactedThinking:
            return nil
        }
    }

    private func openAIInputAudioPart(_ audio: AudioContent) -> [String: Any]? {
        let payloadData: Data?
        if let data = audio.data {
            payloadData = data
        } else if let url = audio.url, url.isFileURL {
            payloadData = try? Data(contentsOf: url)
        } else {
            payloadData = nil
        }

        guard let payloadData, let format = openAIInputAudioFormat(mimeType: audio.mimeType) else {
            return nil
        }

        return [
            "type": "input_audio",
            "input_audio": [
                "data": payloadData.base64EncodedString(),
                "format": format
            ]
        ]
    }

    private func openAIInputAudioFormat(mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        if lower == "audio/wav" || lower == "audio/x-wav" {
            return "wav"
        }
        if lower == "audio/mpeg" || lower == "audio/mp3" {
            return "mp3"
        }
        return nil
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

    private func parseEventType(from jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = object["type"] as? String,
              !type.isEmpty else {
            return nil
        }
        return type
    }

    private func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: FunctionCallState]
    ) throws -> StreamEvent? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponseCreatedEvent.self, from: jsonData)
            return .messageStart(id: event.response.id)
        case "error":
            return .error(Self.decodeErrorEventPayload(jsonData, fallbackMessage: data))

        case "response.output_text.delta":
            let event = try decoder.decode(OutputTextDeltaEvent.self, from: jsonData)
            return .contentDelta(.text(event.delta))

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ReasoningTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.output_item.added":
            let event = try decoder.decode(OutputItemAddedEvent.self, from: jsonData)
            if event.item.type == "function_call" {
                guard let itemID = event.item.id,
                      let callID = event.item.callId,
                      let name = event.item.name else {
                    return nil
                }

                functionCallsByItemID[itemID] = FunctionCallState(callID: callID, name: name)
                return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))
            }

            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.output_item.done":
            let event = try decoder.decode(OutputItemDoneEvent.self, from: jsonData)
            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            if event.item.type == "message",
               let activity = citationSearchActivityFromMessageItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(FunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }

            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return .toolCallDelta(id: state.callID, argumentsDelta: event.delta)

        case "response.function_call_arguments.done":
            let event = try decoder.decode(FunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }
            functionCallsByItemID.removeValue(forKey: event.itemId)

            let args = parseJSONObject(event.arguments)
            return .toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed",
             "response.web_search_call.failed":
            let event = try decoder.decode(WebSearchCallStatusEvent.self, from: jsonData)
            return .searchActivity(
                SearchActivity(
                    id: event.itemId,
                    type: "web_search_call",
                    status: searchStatus(fromEventType: type),
                    arguments: [:],
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
                )
            )

        case "response.completed":
            let event = try decoder.decode(ResponseCompletedEvent.self, from: jsonData)
            let usage = Usage(
                inputTokens: event.response.usage.inputTokens,
                outputTokens: event.response.usage.outputTokens,
                thinkingTokens: event.response.usage.outputTokensDetails?.reasoningTokens,
                cachedTokens: event.response.usage.promptTokensDetails?.cachedTokens
            )
            return .messageEnd(usage: usage)

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponseFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return .error(.providerError(code: errorEvent.response.error?.code ?? "response_failed", message: message))
            }
            return .error(.providerError(code: "response_failed", message: data))

        default:
            return nil
        }
    }

    private func searchActivityFromOutputItem(
        _ item: OutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        guard let id = item.id else { return nil }
        let actionType = item.action?.type ?? "web_search_call"
        return SearchActivity(
            id: id,
            type: actionType,
            status: searchStatus(from: item.status),
            arguments: searchActivityArguments(from: item.action),
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    private func searchActivityArguments(from action: OutputItemAddedEvent.WebSearchAction?) -> [String: AnyCodable] {
        guard let action else { return [:] }
        var out: [String: AnyCodable] = [:]

        if let query = action.query, !query.isEmpty {
            out["query"] = AnyCodable(query)
        }
        if let queries = action.queries, !queries.isEmpty {
            out["queries"] = AnyCodable(queries)
        }
        if let url = action.url, !url.isEmpty {
            out["url"] = AnyCodable(url)
        }
        if let pattern = action.pattern, !pattern.isEmpty {
            out["pattern"] = AnyCodable(pattern)
        }
        if let sources = action.sources, !sources.isEmpty {
            out["sources"] = AnyCodable(
                sources.map { source in
                    var payload: [String: Any] = [
                        "type": source.type,
                        "url": source.url
                    ]
                    if let title = source.title, !title.isEmpty {
                        payload["title"] = title
                    }
                    if let snippet = normalizedSearchPreviewText(source.snippet ?? source.description) {
                        payload["snippet"] = snippet
                    }
                    return payload
                }
            )
        }
        return out
    }

    private func citationSearchActivityFromMessageItem(
        _ item: OutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        let arguments = citationArguments(from: item.content)
        guard !arguments.isEmpty else { return nil }

        let baseID = item.id ?? "message_\(outputIndex ?? -1)"
        return SearchActivity(
            id: "\(baseID):citations",
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    private func citationArguments(from content: [ResponseOutputContent]?) -> [String: AnyCodable] {
        guard let content else { return [:] }

        var sourcePayloads: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for part in content where part.type == "output_text" {
            for annotation in part.annotations ?? [] {
                guard annotation.type == "url_citation" else { continue }
                guard let rawURL = annotation.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                    continue
                }

                let dedupeKey = rawURL.lowercased()
                guard !seenURLs.contains(dedupeKey) else { continue }
                seenURLs.insert(dedupeKey)

                var source: [String: Any] = [
                    "type": annotation.type,
                    "url": rawURL
                ]
                if let title = annotation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    source["title"] = title
                }
                if let snippet = citationPreviewSnippet(
                    text: part.text,
                    startIndex: annotation.startIndex,
                    endIndex: annotation.endIndex
                ) {
                    source["snippet"] = snippet
                }
                sourcePayloads.append(source)
            }
        }

        guard !sourcePayloads.isEmpty else { return [:] }

        var args: [String: AnyCodable] = [
            "sources": AnyCodable(sourcePayloads)
        ]
        if let firstSource = sourcePayloads.first,
           let firstURL = firstSource["url"] as? String {
            args["url"] = AnyCodable(firstURL)
            if let firstTitle = firstSource["title"] as? String, !firstTitle.isEmpty {
                args["title"] = AnyCodable(firstTitle)
            }
        }
        return args
    }

    private func searchStatus(from raw: String?) -> SearchActivityStatus {
        guard let raw, !raw.isEmpty else { return .inProgress }
        return SearchActivityStatus(rawValue: raw)
    }

    private func searchStatus(fromEventType eventType: String) -> SearchActivityStatus {
        if eventType.hasSuffix(".completed") {
            return .completed
        }
        if eventType.hasSuffix(".searching") {
            return .searching
        }
        if eventType.hasSuffix(".failed") {
            return .failed
        }
        return .inProgress
    }

    private func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(AnyCodable.init)
    }

    private func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
        let raw = object.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

private struct FunctionCallState {
    let callID: String
    let name: String
    var argumentsBuffer: String = ""
}

// MARK: - Models Response

private struct ModelsResponse: Codable {
    let data: [ModelData]
}

private struct ModelData: Codable {
    let id: String
}

// MARK: - Streaming Event Types

private struct ResponseCreatedEvent: Codable {
    let response: ResponseInfo

    struct ResponseInfo: Codable {
        let id: String
    }
}

private struct OutputTextDeltaEvent: Codable {
    let delta: String
}

private struct ReasoningTextDeltaEvent: Codable {
    let delta: String
}

private struct ReasoningSummaryTextDeltaEvent: Codable {
    let delta: String
}

private struct ResponseOutputContent: Codable {
    let type: String
    let text: String?
    let annotations: [ResponseOutputAnnotation]?
}

private struct ResponseOutputAnnotation: Codable {
    let type: String
    let url: String?
    let title: String?
    let startIndex: Int?
    let endIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case title
        case startIndex
        case endIndex
        case urlCitation
    }

    private struct URLCitationPayload: Codable {
        let url: String?
        let title: String?
        let startIndex: Int?
        let endIndex: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directType = try container.decodeIfPresent(String.self, forKey: .type)

        let directURL = try container.decodeIfPresent(String.self, forKey: .url)
        let directTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let directStartIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
        let directEndIndex = try container.decodeIfPresent(Int.self, forKey: .endIndex)
        let nestedCitation = try container.decodeIfPresent(URLCitationPayload.self, forKey: .urlCitation)

        if let directType = directType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directType.isEmpty {
            type = directType
        } else if nestedCitation != nil {
            type = "url_citation"
        } else {
            type = ""
        }

        url = directURL ?? nestedCitation?.url
        title = directTitle ?? nestedCitation?.title
        startIndex = directStartIndex ?? nestedCitation?.startIndex
        endIndex = directEndIndex ?? nestedCitation?.endIndex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(startIndex, forKey: .startIndex)
        try container.encodeIfPresent(endIndex, forKey: .endIndex)
    }
}

private struct OutputItemAddedEvent: Codable {
    let outputIndex: Int?
    let sequenceNumber: Int?
    let item: Item

    struct Item: Codable {
        let id: String?
        let type: String
        let callId: String?
        let name: String?
        let status: String?
        let action: WebSearchAction?
        let content: [ResponseOutputContent]?
    }

    struct WebSearchAction: Codable {
        let type: String
        let query: String?
        let queries: [String]?
        let url: String?
        let pattern: String?
        let sources: [Source]?
    }

    struct Source: Codable {
        let type: String
        let url: String
        let title: String?
        let snippet: String?
        let description: String?
    }
}

private struct OutputItemDoneEvent: Codable {
    let outputIndex: Int?
    let sequenceNumber: Int?
    let item: OutputItemAddedEvent.Item
}

private struct WebSearchCallStatusEvent: Codable {
    let itemId: String
    let outputIndex: Int?
    let sequenceNumber: Int?
}

private struct FunctionCallArgumentsDeltaEvent: Codable {
    let itemId: String
    let delta: String
}

private struct FunctionCallArgumentsDoneEvent: Codable {
    let itemId: String
    let arguments: String
}

private struct ResponseCompletedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let usage: UsageInfo

        struct UsageInfo: Codable {
            let inputTokens: Int
            let outputTokens: Int
            let outputTokensDetails: OutputTokensDetails?
            let promptTokensDetails: PromptTokensDetails?

            struct OutputTokensDetails: Codable {
                let reasoningTokens: Int?
            }

            struct PromptTokensDetails: Codable {
                let cachedTokens: Int?
            }
        }
    }
}

private struct ResponseFailedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let error: ErrorInfo?

        struct ErrorInfo: Codable {
            let code: String?
            let message: String?
        }
    }
}
