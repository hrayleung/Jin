import Foundation

/// OpenAI provider adapter (Responses API WebSocket mode)
actor OpenAIWebSocketAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .imageGeneration]

    private let networkManager: NetworkManager
    private let apiKey: String
    private let overrideSession: URLSession?

    private var urlSession: URLSession {
        overrideSession ?? .shared
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var isResponseInFlight = false
    private var previousResponseID: String?
    private var activeTraceSessionID: UUID?

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
        urlSession: URLSession? = nil
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.overrideSession = urlSession
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
        // Route image generation models through the OpenAI HTTP Images API.
        if isImageGenerationModel(modelID) {
            let httpAdapter = OpenAIAdapter(
                providerConfig: ProviderConfig(
                    id: providerConfig.id,
                    name: providerConfig.name,
                    type: .openai,
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
            return try await httpAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: true
            )
        }

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

        isResponseInFlight = true
        let ws: URLSessionWebSocketTask
        do {
            ws = try await openWebSocket()
        } catch {
            isResponseInFlight = false
            throw error
        }

        let socketURL = ws.originalRequest?.url
        activeTraceSessionID = await NetworkDebugLogger.shared.beginWebSocketSession(
            url: socketURL ?? URL(string: "wss://unknown")!,
            headers: ws.originalRequest?.allHTTPHeaderFields
        )
        let traceSessionID = activeTraceSessionID

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ws.send(.string(createEventString))
                    await NetworkDebugLogger.shared.logWebSocketSend(sessionID: traceSessionID, message: createEventString)

                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    let eventDecoder = JSONDecoder()
                    eventDecoder.keyDecodingStrategy = .convertFromSnakeCase

                    while !Task.isCancelled {
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

                        await NetworkDebugLogger.shared.logWebSocketReceive(sessionID: traceSessionID, message: jsonString)

                        guard let eventType = parseEventType(from: jsonString) else {
                            continue
                        }

                        let isTerminalEvent = isTerminalResponseEventType(eventType)

                        if eventType == "response.incomplete",
                           let jsonData = jsonString.data(using: .utf8),
                           let incomplete = try? eventDecoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) {
                            if let notice = incomplete.response.incompleteNoticeMarkdown {
                                continuation.yield(.contentDelta(.text(notice)))
                            }
                            continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
                            break
                        }

                        do {
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
                        } catch is DecodingError {
                            // Be resilient to provider-side schema drift in individual events.
                            // Skip malformed events instead of aborting the whole response stream.
                            if isTerminalEvent {
                                break
                            }
                            continue
                        }

                        if isTerminalEvent {
                            break
                        }
                    }

                    isResponseInFlight = false
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: nil)
                    continuation.finish()
                } catch is CancellationError {
                    await cancelResponseIfPossible()
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: CancellationError())
                    resetWebSocketState()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: error)
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
        await validateAPIKeyViaGET(
            url: try validatedURL("\(resolvedHTTPBaseURLString())/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(resolvedHTTPBaseURLString())/models"),
            apiKey: apiKey,
            accept: nil,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { model in
            var info = ModelCatalog.modelInfo(for: model.id, provider: .openaiWebSocket, name: model.id)
            let contextWindow = model.contextWindow.flatMap { $0 > 0 ? $0 : nil }
            let maxOutputTokens = model.maxTokens.flatMap { $0 > 0 ? $0 : nil }
            if let contextWindow {
                info = ModelInfo(
                    id: info.id,
                    name: info.name,
                    capabilities: info.capabilities,
                    contextWindow: contextWindow,
                    maxOutputTokens: maxOutputTokens ?? info.maxOutputTokens,
                    reasoningConfig: info.reasoningConfig,
                    overrides: info.overrides,
                    catalogMetadata: info.catalogMetadata,
                    isEnabled: info.isEnabled
                )
            } else if let maxOutputTokens {
                info = ModelInfo(
                    id: info.id,
                    name: info.name,
                    capabilities: info.capabilities,
                    contextWindow: info.contextWindow,
                    maxOutputTokens: maxOutputTokens,
                    reasoningConfig: info.reasoningConfig,
                    overrides: info.overrides,
                    catalogMetadata: info.catalogMetadata,
                    isEnabled: info.isEnabled
                )
            }
            return info
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private func openWebSocket() async throws -> URLSessionWebSocketTask {
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
        activeTraceSessionID = nil
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
        let supportsNativeFileInput = supportsNativePDF(modelID)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native

        var body: [String: Any] = [
            "model": modelID,
            "input": try translateInput(
                messages,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ),
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
        let supportsSamplingParameters = supportsOpenAIResponsesSamplingParameters(
            modelID: modelID,
            reasoningEnabled: reasoningEnabled
        )

        // Responses API sampling controls are limited for GPT-5 family models.
        if supportsSamplingParameters {
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

        if let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
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
            guard key != "prompt_cache_min_tokens", key != "service_tier" else {
                continue
            }
            if !supportsSamplingParameters, key == "temperature" || key == "top_p" {
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

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return OpenAIAdapter.imageGenerationModelIDs.contains(modelID.lowercased())
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: providerConfig.type, modelID: modelID)
    }

    // Shared MIME type set defined in AdapterUtilities.swift

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        isOpenAIAudioInputModelID(lowerModelID)
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

}

// MARK: - Models Response

private struct ModelsResponse: Codable {
    let data: [ModelData]
}

private struct ModelData: Codable {
    let id: String
    let contextWindow: Int?
    let maxTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case contextWindow = "context_window"
        case maxTokens = "max_tokens"
    }
}
