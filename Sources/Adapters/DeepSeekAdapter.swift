import Foundation

/// DeepSeek official provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.deepseek.com
/// - Endpoint: POST /chat/completions
/// - Models: `deepseek-chat`, `deepseek-reasoner`, `deepseek-v3.2-exp`, ...
actor DeepSeekAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .reasoning]

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
            let response = try OpenAIChatCompletionsCore.decodeResponse(data)
            return OpenAIChatCompletionsCore.makeNonStreamingStream(
                response: response,
                reasoningField: .reasoningContent
            )
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoningContent
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURLRoot)/v1/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: URL(string: "\(baseURLRoot)/v1/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        if trimmed.hasSuffix("/v1") {
            let withoutV1 = String(trimmed.dropLast(3))
            return withoutV1.hasSuffix("/") ? String(withoutV1.dropLast()) : withoutV1
        }

        return trimmed
    }

    private var isDefaultHost: Bool {
        guard let url = URL(string: baseURLRoot), let host = url.host?.lowercased() else { return false }
        return host == "api.deepseek.com"
    }

    private func chatCompletionsURL(for modelID: String) throws -> URL {
        let lower = modelID.lowercased()
        if isDefaultHost, lower.contains("v3.2-exp") {
            return try requireURL("\(baseURLRoot)/beta/chat/completions")
        }

        return try requireURL("\(baseURLRoot)/v1/chat/completions")
    }

    private func requireURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw) else {
            throw LLMError.invalidRequest(message: "Invalid DeepSeek base URL.")
        }
        return url
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try chatCompletionsURL(for: modelID))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        let isReasoningModel = modelID.lowercased().contains("reasoner")
        if !isReasoningModel {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false {
                body["reasoning"] = false
            } else if isReasoningModel {
                body["reasoning"] = true
            }
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
        let (visibleContent, reasoningContent) = splitContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system, .user:
            dict["content"] = visibleContent

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            dict["content"] = visibleContent.isEmpty ? (hasToolCalls ? NSNull() : "") : visibleContent

            if !reasoningContent.isEmpty {
                dict["reasoning_content"] = reasoningContent
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCalls(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, reasoning: String) {
        var visibleParts: [String] = []
        visibleParts.reserveCapacity(parts.count)

        var reasoningParts: [String] = []
        reasoningParts.reserveCapacity(2)

        for part in parts {
            switch part {
            case .text(let text):
                visibleParts.append(text)
            case .file(let file):
                visibleParts.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .image(let image):
                if image.url != nil || image.data != nil {
                    visibleParts.append("[Image attachment omitted: this provider does not support vision in Jin yet]")
                }
            case .thinking(let thinking):
                reasoningParts.append(thinking.text)
            case .redactedThinking, .audio:
                continue
            }
        }

        return (visibleParts.joined(), reasoningParts.joined())
    }

    private func translateToolCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map { call in
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

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        var propertiesDict: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            propertiesDict[key] = prop.toDictionary()
        }

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.parameters.type,
                    "properties": propertiesDict,
                    "required": tool.parameters.required
                ]
            ]
        ]
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

    private func makeModelInfo(id: String) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig? = nil

        if lower.contains("reasoner") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: 128000,
            reasoningConfig: reasoningConfig
        )
    }
}
