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
                    var functionCallsByItemID: [String: FunctionCallState] = [:]

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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)

        return response.data.map { model in
            var caps: ModelCapability = [.streaming, .toolCalling, .promptCaching]
            var reasoningConfig: ModelReasoningConfig?

            if model.id.contains("gpt-5") || model.id.contains("o1") || model.id.contains("o3") || model.id.contains("o4") {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            if model.id.contains("gpt-4o") || model.id.contains("gpt-5") || model.id.contains("o3") || model.id.contains("o4") {
                caps.insert(.vision)
            }

            // Native PDF support for GPT-5.2+, o3+, o4+ (all have vision)
            if (model.id.contains("gpt-5.2") || model.id.contains("o3") || model.id.contains("o4")) && caps.contains(.vision) {
                caps.insert(.nativePDF)
            }

            let contextWindow: Int
            if model.id.contains("gpt-5.2") {
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
        var request = URLRequest(url: URL(string: "\(baseURL)/responses")!)
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
            if let cacheKey = normalizedContextCacheString(controls.contextCache?.cacheKey) {
                body["prompt_cache_key"] = cacheKey
            }
            if let retention = controls.contextCache?.ttl?.providerTTLString {
                body["prompt_cache_retention"] = retention
            }
            if let minTokens = controls.contextCache?.minTokensThreshold, minTokens > 0 {
                body["prompt_cache_min_tokens"] = minTokens
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
                "effort": mapReasoningEffort(effort)
            ]

            // Add summary control if specified
            if let summary = controls.reasoning?.summary {
                reasoningDict["summary"] = summary.rawValue
            }

            body["reasoning"] = reasoningDict
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true {
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
            body[key] = value.value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
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
        // GPT-5.2+, o3+, o4+ support native PDF
        return modelID.contains("gpt-5.2") || modelID.contains("o3") || modelID.contains("o4")
    }

    private func normalizedContextCacheString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            guard event.item.type == "function_call",
                  let itemID = event.item.id,
                  let callID = event.item.callId,
                  let name = event.item.name else {
                return nil
            }

            functionCallsByItemID[itemID] = FunctionCallState(callID: callID, name: name)
            return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))

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

private struct OutputItemAddedEvent: Codable {
    let item: Item

    struct Item: Codable {
        let id: String?
        let type: String
        let callId: String?
        let name: String?
    }
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
            let message: String
        }
    }
}

// MARK: - Non-streaming Response Types

private struct ResponsesAPIResponse: Codable {
    let id: String
    let output: [OutputItem]
    let usage: UsageInfo?

    struct OutputItem: Codable {
        let type: String
        let content: [Content]?
        let summary: [Content]?

        struct Content: Codable {
            let type: String
            let text: String?
        }
    }

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

    var outputTextParts: [String] {
        output.flatMap { item in
            switch item.type {
            case "message":
                return item.content?.compactMap { $0.type == "output_text" ? $0.text : nil } ?? []
            case "reasoning":
                return item.summary?.compactMap { $0.type == "summary_text" ? $0.text : nil } ?? []
            default:
                return []
            }
        }
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        return Usage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            thinkingTokens: usage.outputTokensDetails?.reasoningTokens,
            cachedTokens: usage.promptTokensDetails?.cachedTokens
        )
    }
}
