import Foundation

/// Cohere official provider adapter (Chat API v2).
///
/// Docs:
/// - Base URL: https://api.cohere.com/v2
/// - Endpoint: POST /chat (streaming via SSE when `stream=true`)
actor CohereAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling]

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
            let response = try decodeChatResponse(data)
            return makeNonStreamingStream(response: response)
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return makeStreamingStream(sseStream: sseStream)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: try validatedURL("\(baseURL)/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

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
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)

        // Cohere models response isn't OpenAI-shaped; parse defensively.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let models = json["models"] as? [[String: Any]] {
                let ids = models.compactMap { dict in
                    (dict["name"] as? String)
                        ?? (dict["id"] as? String)
                        ?? (dict["model"] as? String)
                }
                if !ids.isEmpty {
                    return ids.map(makeModelInfo(id:))
                }
            }

            if let dataModels = json["data"] as? [[String: Any]] {
                let ids = dataModels.compactMap { dict in
                    (dict["id"] as? String)
                        ?? (dict["name"] as? String)
                        ?? (dict["model"] as? String)
                }
                if !ids.isEmpty {
                    return ids.map(makeModelInfo(id:))
                }
            }
        }

        return providerConfig.models
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? providerConfig.type.defaultBaseURL ?? "https://api.cohere.com/v2")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/chat") {
            trimmed = String(trimmed.dropLast(5))
            trimmed = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }

        if lower.hasSuffix("/v2") {
            return trimmed
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v2"
        }

        return trimmed
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try validatedURL("\(baseURL)/chat"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }

        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let topP = controls.topP {
            // Cohere uses `p` for nucleus sampling.
            body["p"] = topP
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func translateMessages(_ messages: [Message]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(messages.count + 4)

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        out.append([
                            "role": "tool",
                            "tool_call_id": result.toolCallID,
                            "content": result.content
                        ])
                    }
                }

            case .system, .user, .assistant:
                out.append(translateNonToolMessage(message))

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        out.append([
                            "role": "tool",
                            "tool_call_id": result.toolCallID,
                            "content": result.content
                        ])
                    }
                }
            }
        }

        return out
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let visibleContent = renderVisibleContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue,
            "content": visibleContent
        ]

        if message.role == .assistant,
           let toolCalls = message.toolCalls,
           !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": encodeJSONObject(call.arguments)
                    ]
                ]
            }
        }

        return dict
    }

    private func renderVisibleContent(_ parts: [ContentPart]) -> String {
        var segments: [String] = []
        segments.reserveCapacity(parts.count)

        for part in parts {
            switch part {
            case .text(let text):
                segments.append(text)
            case .file(let file):
                segments.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .image, .video, .audio, .thinking, .redactedThinking:
                continue
            }
        }

        return segments.joined(separator: "\n")
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

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                    "required": tool.parameters.required
                ]
            ]
        ]
    }

    // MARK: - Decode / Stream Mapping

    private struct ChatResponse: Decodable {
        struct ChatMessage: Decodable {
            struct ContentPart: Decodable {
                let type: String?
                let text: String?
            }

            struct ToolCall: Decodable {
                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }

                let id: String?
                let type: String?
                let function: Function?
            }

            let role: String?
            let content: [ContentPart]?
            let toolCalls: [ToolCall]?
        }

        struct UsageInfo: Decodable {
            struct Tokens: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
            }

            let tokens: Tokens?
        }

        let id: String?
        let finishReason: String?
        let message: ChatMessage?
        let usage: UsageInfo?
    }

    private func decodeChatResponse(_ data: Data) throws -> ChatResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(ChatResponse.self, from: data)
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    private func makeNonStreamingStream(
        response: ChatResponse
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let messageID = response.id ?? UUID().uuidString
            continuation.yield(.messageStart(id: messageID))

            if let parts = response.message?.content {
                let text = parts
                    .compactMap { part -> String? in
                        guard (part.type ?? "").lowercased() == "text" else { return nil }
                        return part.text
                    }
                    .joined(separator: "")
                if !text.isEmpty {
                    continuation.yield(.contentDelta(.text(text)))
                }
            }

            if let toolCalls = response.message?.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    let id = call.id ?? UUID().uuidString
                    let name = call.function?.name ?? ""
                    let argsString = call.function?.arguments ?? "{}"
                    let args = parseJSONObject(argsString)
                    let toolCall = ToolCall(id: id, name: name, arguments: args)
                    continuation.yield(.toolCallStart(toolCall))
                    continuation.yield(.toolCallEnd(toolCall))
                }
            }

            let usage = response.usage.flatMap { info -> Usage? in
                guard let input = info.tokens?.inputTokens,
                      let output = info.tokens?.outputTokens else { return nil }
                return Usage(inputTokens: input, outputTokens: output)
            }

            continuation.yield(.messageEnd(usage: usage))
            continuation.finish()
        }
    }

    private struct ToolCallState {
        var callID: String
        var name: String
        var didEmitStart: Bool
        var argumentsBuffer: String
    }

    private func makeStreamingStream(
        sseStream: AsyncThrowingStream<SSEEvent, Error>
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    var messageID: String = UUID().uuidString
                    var pendingUsage: Usage?
                    var toolCallsByID: [String: ToolCallState] = [:]

                    for try await event in sseStream {
                        switch event {
                        case .done:
                            continuation.yield(.messageEnd(usage: pendingUsage))
                            continue

                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8),
                                  let payload = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                continue
                            }

                            let type = (payload["type"] as? String) ?? ""

                            if type == "message-start" {
                                if !didStart {
                                    if let id = payload["id"] as? String, !id.isEmpty {
                                        messageID = id
                                    }
                                    continuation.yield(.messageStart(id: messageID))
                                    didStart = true
                                }
                                continue
                            }

                            if !didStart {
                                continuation.yield(.messageStart(id: messageID))
                                didStart = true
                            }

                            switch type {
                            case "content-delta":
                                if let text = (((payload["delta"] as? [String: Any])?["message"] as? [String: Any])?["content"] as? [String: Any])?["text"] as? String,
                                   !text.isEmpty {
                                    continuation.yield(.contentDelta(.text(text)))
                                }

                            case "tool-call-start", "tool-call-delta", "tool-call-end":
                                guard let toolCalls = (((payload["delta"] as? [String: Any])?["message"] as? [String: Any])?["tool_calls"] as? [[String: Any]]) else {
                                    break
                                }

                                for call in toolCalls {
                                    let id = (call["id"] as? String) ?? ""
                                    guard !id.isEmpty else { continue }

                                    var state = toolCallsByID[id] ?? ToolCallState(callID: id, name: "", didEmitStart: false, argumentsBuffer: "")

                                    if let fn = call["function"] as? [String: Any] {
                                        if let name = fn["name"] as? String, !name.isEmpty {
                                            state.name = name
                                        }

                                        if let args = fn["arguments"] as? String, !args.isEmpty {
                                            if type == "tool-call-end" {
                                                state.argumentsBuffer = args
                                            } else {
                                                state.argumentsBuffer.append(args)
                                            }
                                            continuation.yield(.toolCallDelta(id: id, argumentsDelta: args))
                                        }
                                    }

                                    if state.didEmitStart == false, !state.name.isEmpty {
                                        state.didEmitStart = true
                                        continuation.yield(.toolCallStart(ToolCall(id: id, name: state.name, arguments: [:])))
                                    }

                                    if type == "tool-call-end", !state.name.isEmpty {
                                        let args = parseJSONObject(state.argumentsBuffer)
                                        continuation.yield(.toolCallEnd(ToolCall(id: id, name: state.name, arguments: args)))
                                    }

                                    toolCallsByID[id] = state
                                }

                            case "message-end":
                                pendingUsage = usageFromMessageEnd(payload)

                                // Ensure we emit toolCallEnd for any in-progress tool calls.
                                for (_, state) in toolCallsByID where !state.callID.isEmpty && !state.name.isEmpty {
                                    let args = parseJSONObject(state.argumentsBuffer)
                                    continuation.yield(.toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args)))
                                }

                                continuation.yield(.messageEnd(usage: pendingUsage))

                            default:
                                break
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

    private func usageFromMessageEnd(_ payload: [String: Any]) -> Usage? {
        guard let delta = payload["delta"] as? [String: Any],
              let usage = delta["usage"] as? [String: Any],
              let tokens = usage["tokens"] as? [String: Any] else {
            return nil
        }

        guard let input = intValue(tokens["input_tokens"]),
              let output = intValue(tokens["output_tokens"]) else {
            return nil
        }

        return Usage(inputTokens: input, outputTokens: output)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let num = value as? NSNumber { return num.intValue }
        if let str = value as? String { return Int(str) }
        return nil
    }

    private func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(AnyCodable.init)
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
    }
}

