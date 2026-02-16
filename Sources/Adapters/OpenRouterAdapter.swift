import Foundation

/// OpenRouter provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://openrouter.ai/api/v1
/// - Endpoint: POST /chat/completions
/// - Models: GET /models
actor OpenRouterAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

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
                reasoningField: .reasoning
            )
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoning
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/key")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

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
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://openrouter.ai/api/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed),
           url.host?.lowercased().contains("openrouter.ai") == true,
           (url.path.isEmpty || url.path == "/") {
            return "\(trimmed)/api/v1"
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
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

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
            body["top_p"] = topP
        }

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                body["reasoning"] = ["effort": "none"]
            } else if let effort = reasoning.effort {
                body["reasoning"] = ["effort": mapReasoningEffort(effort)]
            }
        }

        if controls.webSearch?.enabled == true {
            var plugins = body["plugins"] as? [[String: Any]] ?? []
            plugins.append(["id": "web"])
            body["plugins"] = plugins
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
        let (visibleContent, thinkingContent, hasRichUserContent) = splitContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = visibleContent

        case .user:
            if hasRichUserContent {
                dict["content"] = translateUserContentParts(message.content)
            } else {
                dict["content"] = visibleContent
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if visibleContent.isEmpty {
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = visibleContent
            }

            if !thinkingContent.isEmpty {
                dict["reasoning"] = thinkingContent
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCalls(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
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
                let text = AttachmentPromptRenderer.fallbackText(for: file)
                out.append([
                    "type": "text",
                    "text": text
                ])

            case .audio(let audio):
                if let inputAudio = inputAudioPart(audio) {
                    out.append(inputAudio)
                }

            case .thinking, .redactedThinking, .video:
                continue
            }
        }

        return out
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

    private func inputAudioPart(_ audio: AudioContent) -> [String: Any]? {
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

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, thinking: String, hasRichUserContent: Bool) {
        var visibleParts: [String] = []
        visibleParts.reserveCapacity(parts.count)

        var thinkingParts: [String] = []
        var hasRichUserContent = false

        for part in parts {
            switch part {
            case .text(let text):
                visibleParts.append(text)
            case .file(let file):
                visibleParts.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .image:
                hasRichUserContent = true
            case .audio:
                hasRichUserContent = true
            case .thinking(let thinking):
                thinkingParts.append(thinking.text)
            case .redactedThinking, .video:
                break
            }
        }

        return (visibleParts.joined(), thinkingParts.joined(), hasRichUserContent)
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

    private func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
        let raw = object.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    private func makeModelInfo(from model: OpenRouterModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let inputModalities = Set((model.architecture?.inputModalities ?? []).map { $0.lowercased() })

        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?
        let contextWindow = 128000

        if lower.contains("/gpt") || lower.contains("/o1") || lower.contains("/o3") || lower.contains("/o4") || lower.contains("reason") || lower.contains("thinking") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        }

        if inputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
            || lower.contains("vision")
            || lower.contains("image")
            || lower.contains("/gpt-4o")
            || lower.contains("/gpt-5")
            || lower.contains("/gemini")
            || lower.contains("/claude") {
            caps.insert(.vision)
        }

        if inputModalities.contains(where: { $0.contains("audio") }) {
            caps.insert(.audio)
        }
        if supportsAudioInputModelID(lower) {
            caps.insert(.audio)
        }

        if lower.contains("image") {
            caps.insert(.imageGeneration)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        if lowerModelID.contains("gpt-audio")
            || lowerModelID.contains("audio-preview")
            || lowerModelID.contains("realtime")
            || lowerModelID.contains("voxtral")
            || lowerModelID.contains("qwen3-asr")
            || lowerModelID.contains("qwen3-omni") {
            return true
        }

        if (lowerModelID.contains("gemini-2.5") || lowerModelID.contains("gemini-3") || lowerModelID.contains("gemini-2.0"))
            && !lowerModelID.contains("-image")
            && !lowerModelID.contains("imagen") {
            return true
        }

        return false
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let architecture: Architecture?
    }

    struct Architecture: Decodable {
        let inputModalities: [String]?
    }
}
