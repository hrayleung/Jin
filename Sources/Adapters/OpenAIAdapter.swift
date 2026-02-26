import Foundation

/// OpenAI provider adapter (Responses API)
actor OpenAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching]

    private let networkManager: NetworkManager
    private let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // OpenAI currently documents audio input support primarily on Chat Completions.
        // Route audio-bearing requests through the OpenAI-compatible Chat Completions path.
        if shouldRouteToChatCompletionsForAudio(messages: messages, modelID: modelID) {
            let chatCompletionsAdapter = OpenAICompatibleAdapter(
                providerConfig: providerConfig,
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await chatCompletionsAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: streaming
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
            let response = try decoder.decode(ResponsesAPIResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for activity in response.searchActivities {
                    continuation.yield(.searchActivity(activity))
                }

                for text in response.outputTextParts {
                    continuation.yield(.contentDelta(.text(text)))
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if let streamEvent = try parseSSEEvent(
                                type: type,
                                data: data,
                                functionCallsByItemID: &functionCallsByItemID
                            ) {
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
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { model in
            ModelCatalog.modelInfo(for: model.id, provider: .openai, name: model.id)
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.openai.com/v1"
    }

    private func buildRequest(
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

        let supportsNativeFileInput = supportsNativePDF(modelID)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native

        var body: [String: Any] = [
            "model": modelID,
            "input": translateInput(
                messages,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ),
            "stream": streaming
        ]

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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func mergedIncludeFields(_ existing: Any?, adding field: String) -> [String] {
        let existingStrings: [String]
        if let strings = existing as? [String] {
            existingStrings = strings
        } else if let anyArray = existing as? [Any] {
            existingStrings = anyArray.compactMap { $0 as? String }
        } else {
            existingStrings = []
        }

        var seen: Set<String> = []
        var out: [String] = []
        for raw in existingStrings + [field] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
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
        JinModelSupport.supportsNativePDF(providerType: .openai, modelID: modelID)
    }

    // MIME types supported natively by OpenAI Responses API via input_file
    private static let openAISupportedFileMIMETypes: Set<String> = [
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document", // docx
        "application/msword",                                                        // doc
        "application/vnd.oasis.opendocument.text",                                  // odt
        "application/rtf", "text/rtf",                                              // rtf
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",        // xlsx
        "application/vnd.ms-excel",                                                 // xls
        "text/csv",                                                                 // csv
        "text/tab-separated-values",                                                // tsv
        "application/vnd.openxmlformats-officedocument.presentationml.presentation", // pptx
        "application/vnd.ms-powerpoint",                                            // ppt
        "text/plain",                                                               // txt
        "text/markdown", "text/x-markdown",                                        // md
        "application/json",                                                         // json
        "text/html",                                                                // html
        "application/xml", "text/xml",                                              // xml
    ]

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

    private func translateInput(
        _ messages: [Message],
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) -> [[String: Any]] {
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
                if let translated = translateMessage(
                    message,
                    supportsNativeFileInput: supportsNativeFileInput,
                    allowNativePDF: allowNativePDF
                ) {
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

    private func translateMessage(
        _ message: Message,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) -> [String: Any]? {
        let content = message.content.compactMap { part in
            translateContentPart(
                part,
                role: message.role,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            )
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

    private func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) -> [String: Any]? {
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
            let shouldAllowNativeFileUpload =
                supportsNativeFileInput &&
                Self.openAISupportedFileMIMETypes.contains(file.mimeType) &&
                (file.mimeType != "application/pdf" || allowNativePDF)

            if shouldAllowNativeFileUpload {
                // Remote URL: use file_url directly (Responses API supports this)
                if let url = file.url, !url.isFileURL {
                    return [
                        "type": "input_file",
                        "file_url": url.absoluteString
                    ]
                }

                // Load data from file URL or use existing data
                let fileData: Data?
                if let data = file.data {
                    fileData = data
                } else if let url = file.url, url.isFileURL {
                    fileData = try? Data(contentsOf: url)
                } else {
                    fileData = nil
                }

                if let fileData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:\(file.mimeType);base64,\(fileData.base64EncodedString())"
                    ]
                }
            }

            // Fallback to text extraction for unsupported types or models
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
            if event.item.type == "function_call" {
                guard let itemID = event.item.id,
                      let callID = event.item.callId,
                      let name = event.item.name else {
                    return nil
                }

                functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
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
            let event = try decoder.decode(ResponsesAPIOutputItemDoneEvent.self, from: jsonData)
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

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed",
             "response.web_search_call.failed":
            let event = try decoder.decode(ResponsesAPIWebSearchCallStatusEvent.self, from: jsonData)
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
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            let usage = Usage(
                inputTokens: event.response.usage.inputTokens,
                outputTokens: event.response.usage.outputTokens,
                thinkingTokens: event.response.usage.outputTokensDetails?.reasoningTokens,
                cachedTokens: event.response.usage.promptTokensDetails?.cachedTokens
            )
            return .messageEnd(usage: usage)

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

    private func searchActivityFromOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        guard let id = item.id else { return nil }
        let actionType = item.action?.type ?? "web_search_call"
        return SearchActivity(
            id: id,
            type: actionType,
            status: searchStatus(from: item.status),
            arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action),
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    private func citationSearchActivityFromMessageItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        let arguments = ResponsesAPIResponse.citationArguments(from: item.content)
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
}

// MARK: - Models Response

private struct ModelsResponse: Codable {
    let data: [ModelData]
}

private struct ModelData: Codable {
    let id: String
}
