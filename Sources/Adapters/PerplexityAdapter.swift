import Foundation

/// Perplexity Sonar (OpenAI-compatible Chat Completions)
actor PerplexityAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    /// Perplexity supports streaming, vision, and web-grounded search. Function calling is OpenAI-compatible.
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
            let response = try OpenAIChatCompletionsCore.decodeResponse(data)
            return OpenAIChatCompletionsCore.makeNonStreamingStream(
                response: response,
                reasoningField: .reasoningOrReasoningContent
            )
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoningOrReasoningContent
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        // Perplexity does not expose a lightweight auth check; use a minimal completion with small max_tokens.
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "model": "sonar",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        if !providerConfig.models.isEmpty {
            return providerConfig.models
        }

        return [
            ModelInfo(
                id: "sonar",
                name: "Sonar",
                capabilities: [.streaming, .vision],
                contextWindow: 128_000,
                reasoningConfig: nil
            ),
            ModelInfo(
                id: "sonar-pro",
                name: "Sonar Pro",
                capabilities: [.streaming, .toolCalling, .vision],
                contextWindow: 200_000,
                reasoningConfig: nil
            ),
            ModelInfo(
                id: "sonar-reasoning-pro",
                name: "Sonar Reasoning Pro",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 128_000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "sonar-deep-research",
                name: "Sonar Deep Research",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 128_000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            )
        ]
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.perplexity.defaultBaseURL ?? "https://api.perplexity.ai")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let reasoningEffort = mapReasoningEffort(controls.reasoning) {
            body["reasoning_effort"] = reasoningEffort
        }

        if let webSearch = controls.webSearch {
            if webSearch.enabled == false {
                body["disable_search"] = true
            } else if let contextSize = webSearch.contextSize {
                body["web_search_options"] = [
                    "search_context_size": contextSize.rawValue
                ]
            }
        }

        if containsImage(messages) {
            body["has_image_url"] = true
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        if !controls.providerSpecific.isEmpty {
            deepMerge(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
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
        let (visibleContent, thinkingContent, hasImage) = splitContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = visibleContent

        case .assistant:
            dict["content"] = visibleContent
            if let thinkingContent {
                dict["reasoning"] = thinkingContent
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
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

        case .user:
            if hasImage {
                dict["content"] = translateUserContentParts(message.content)
            } else {
                dict["content"] = visibleContent
            }

        case .tool:
            dict["content"] = visibleContent
        }

        return dict
    }

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, thinking: String?, hasImage: Bool) {
        var visibleSegments: [String] = []
        var thinkingSegments: [String] = []
        var hasImage = false

        for part in parts {
            switch part {
            case .text(let text):
                visibleSegments.append(text)
            case .file(let file):
                visibleSegments.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .thinking(let thinking):
                let text = thinking.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    thinkingSegments.append(text)
                }
            case .redactedThinking, .audio, .video:
                continue
            case .image:
                hasImage = true
            }
        }

        let visible = visibleSegments.joined(separator: "\n")
        let thinking = thinkingSegments.isEmpty ? nil : thinkingSegments.joined(separator: "\n")
        return (visible, thinking, hasImage)
    }

    private func translateUserContentParts(_ parts: [ContentPart]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(parts.count)

        for part in parts {
            switch part {
            case .text(let text):
                out.append([
                    "type": "text",
                    "text": text
                ])

            case .image(let image):
                if let urlString = imageURLString(image) {
                    out.append([
                        "type": "image_url",
                        "image_url": [
                            "url": urlString
                        ]
                    ])
                }

            case .file(let file):
                out.append([
                    "type": "text",
                    "text": AttachmentPromptRenderer.fallbackText(for: file)
                ])

            case .thinking, .redactedThinking, .audio, .video:
                continue
            }
        }

        return out
    }

    private func containsImage(_ messages: [Message]) -> Bool {
        for message in messages {
            if message.content.contains(where: { part in
                if case .image = part { return true }
                return false
            }) {
                return true
            }
        }
        return false
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

    private func mapReasoningEffort(_ reasoning: ReasoningControls?) -> String? {
        guard let reasoning else { return nil }
        guard reasoning.enabled else { return nil }

        switch reasoning.effort ?? .medium {
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        case .none:
            return nil
        }
    }

    private func deepMerge(into base: inout [String: Any], additional: [String: Any]) {
        for (key, value) in additional {
            if var baseDict = base[key] as? [String: Any], let addDict = value as? [String: Any] {
                deepMerge(into: &baseDict, additional: addDict)
                base[key] = baseDict
            } else {
                base[key] = value
            }
        }
    }
}
