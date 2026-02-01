import Foundation

/// xAI provider adapter (OpenAI-compatible Responses API)
actor XAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

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
            let response = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data)

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
                            if type == "response.completed" {
                                if let encrypted = extractEncryptedReasoningEncryptedContent(from: data) {
                                    continuation.yield(.thinkingDelta(.redacted(data: encrypted)))
                                }
                            }
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
            var caps: ModelCapability = [.streaming, .toolCalling]

            if model.id.contains("grok") {
                caps.insert(.vision)
                caps.insert(.reasoning)
            }

            return ModelInfo(
                id: model.id,
                name: model.id,
                capabilities: caps,
                contextWindow: 128000,
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

        var body: [String: Any] = [
            "model": modelID,
            "input": translateInput(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        if supportsReasoningEffort(modelID: modelID), let reasoning = controls.reasoning, reasoning.enabled, let effort = reasoning.effort {
            body["reasoning_effort"] = mapReasoningEffort(effort)
        }

        if supportsEncryptedReasoning(modelID: modelID) {
            var include = Set((body["include"] as? [String]) ?? [])
            include.insert("reasoning.encrypted_content")
            body["include"] = Array(include).sorted()
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true {
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

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "low"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    private func supportsReasoningEffort(modelID: String) -> Bool {
        // Per xAI docs: reasoning_effort is only supported for grok-3-mini (not Grok 4/4.1).
        modelID.contains("grok-3-mini")
    }

    private func supportsEncryptedReasoning(modelID: String) -> Bool {
        // Per xAI docs: Grok 4 reasoning can be returned encrypted via include:["reasoning.encrypted_content"].
        // Avoid requesting for explicit non-reasoning variants.
        guard modelID.contains("grok-4") else { return false }
        return !modelID.contains("non-reasoning")
    }

    private func extractEncryptedReasoningEncryptedContent(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return findEncryptedContent(in: object)
    }

    private func findEncryptedContent(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let type = dict["type"] as? String,
               type == "reasoning",
               let encrypted = dict["encrypted_content"] as? String {
                return encrypted
            }

            if let encrypted = dict["encrypted_content"] as? String {
                return encrypted
            }

            for value in dict.values {
                if let found = findEncryptedContent(in: value) {
                    return found
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for element in array {
                if let found = findEncryptedContent(in: element) {
                    return found
                }
            }
            return nil
        }

        return nil
    }

    private func translateInput(_ messages: [Message]) -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": result.content
                        ])
                    }
                }

            case .system, .user, .assistant:
                items.append(translateMessage(message))

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": result.content
                        ])
                    }
                }
            }
        }

        return items
    }

    private func translateMessage(_ message: Message) -> [String: Any] {
        let content = message.content.compactMap(translateContentPart)

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    private func translateContentPart(_ part: ContentPart) -> [String: Any]? {
        switch part {
        case .text(let text):
            return [
                "type": "input_text",
                "text": text
            ]

        case .image(let image):
            if let url = image.url {
                return [
                    "type": "input_image",
                    "image_url": url.absoluteString
                ]
            }
            if let data = image.data {
                return [
                    "type": "input_image",
                    "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                ]
            }
            return nil

        case .thinking, .redactedThinking, .file, .audio:
            return nil
        }
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        var propertiesDict: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            propertiesDict[key] = prop.toDictionary()
        }

        return [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": propertiesDict,
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
                thinkingTokens: event.response.usage.outputTokensDetails?.reasoningTokens
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

            struct OutputTokensDetails: Codable {
                let reasoningTokens: Int?
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

        struct OutputTokensDetails: Codable {
            let reasoningTokens: Int?
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
            thinkingTokens: usage.outputTokensDetails?.reasoningTokens
        )
    }
}
