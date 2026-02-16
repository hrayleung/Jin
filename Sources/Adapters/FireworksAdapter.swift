import Foundation

/// Fireworks provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.fireworks.ai/inference/v1
/// - Endpoint: POST /chat/completions
/// - Models: `fireworks/kimi-k2p5`, `fireworks/glm-4p7`, `fireworks/glm-5`, `fireworks/minimax-m2p5`, ...
actor FireworksAdapter: LLMProviderAdapter {
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
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.fireworks.ai/inference/v1"
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

        // Fireworks reasoning controls:
        // - Most models: `reasoning_effort` supports `none` / `low` / `medium` / `high`.
        // - MiniMax M2 family: only `low` / `medium` / `high`; omitting the field defaults to `medium`.
        let isMiniMaxM2FamilyModel = isFireworksMiniMaxM2FamilyModel(modelID)
        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none {
                if !isMiniMaxM2FamilyModel {
                    body["reasoning_effort"] = "none"
                }
            } else if let effort = reasoning.effort {
                body["reasoning_effort"] = mapReasoningEffort(effort)
            }
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            if key == "reasoning_effort", isMiniMaxM2FamilyModel {
                if let normalized = normalizeMiniMaxReasoningEffort(value.value) {
                    body[key] = normalized
                }
                continue
            }

            if key == "reasoning_history" {
                if let normalized = normalizeReasoningHistory(value.value, modelID: modelID) {
                    body[key] = normalized
                }
                continue
            }

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
                // OpenAI-style: assistant content can be null when tool_calls exist.
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = visibleContent
            }

            if !thinkingContent.isEmpty {
                // Fireworks returns this as `reasoning_content`; preserving it improves multi-turn stability for supported models.
                dict["reasoning_content"] = thinkingContent
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCalls(toolCalls)
            }

        case .tool:
            // Not used here; tool results are expanded in translateMessages(_:).
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

        guard let payloadData else {
            return nil
        }

        let mimeType = normalizedAudioMIMEType(audio.mimeType)
        let dataURL = "data:\(mimeType);base64,\(payloadData.base64EncodedString())"

        return [
            "type": "audio_url",
            "audio_url": [
                "url": dataURL
            ]
        ]
    }

    private func normalizedAudioMIMEType(_ mimeType: String) -> String {
        let lower = mimeType.lowercased()
        if lower == "audio/x-wav" {
            return "audio/wav"
        }
        if lower == "audio/x-m4a" {
            return "audio/m4a"
        }
        if lower.hasPrefix("audio/") {
            return lower
        }
        return "audio/wav"
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
        // Fireworks accepts: low, medium, high across reasoning models.
        // For non-MiniMax families, we may also send `none` to disable reasoning.
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

    private func normalizeMiniMaxReasoningEffort(_ raw: Any) -> String? {
        guard let effort = raw as? String else { return nil }
        switch effort.lowercased() {
        case "low":
            return "low"
        case "medium":
            return "medium"
        case "high":
            return "high"
        default:
            return nil
        }
    }

    private func normalizeReasoningHistory(_ raw: Any, modelID: String) -> String? {
        guard let history = raw as? String else { return nil }
        let normalized = history.lowercased()
        return supportedReasoningHistoryValues(for: modelID).contains(normalized) ? normalized : nil
    }

    private func supportedReasoningHistoryValues(for modelID: String) -> Set<String> {
        if isFireworksMiniMaxM2FamilyModel(modelID) {
            return ["interleaved", "disabled"]
        }

        if isFireworksModelID(modelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(modelID, canonicalID: "glm-4p7")
            || isFireworksModelID(modelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }

        return []
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        let isKimiK2p5 = isFireworksModelID(id, canonicalID: "kimi-k2p5")
        let isGLM4p7 = isFireworksModelID(id, canonicalID: "glm-4p7")
        let isGLM5 = isFireworksModelID(id, canonicalID: "glm-5")
        let isMiniMaxM2 = isFireworksModelID(id, canonicalID: "minimax-m2")
        let isMiniMaxM2p1 = isFireworksModelID(id, canonicalID: "minimax-m2p1")
        let isMiniMaxM2p5 = isFireworksModelID(id, canonicalID: "minimax-m2p5")
        let isQwen3OmniInstruct = isFireworksModelID(id, canonicalID: "qwen3-omni-30b-a3b-instruct")
        let isQwen3OmniThinking = isFireworksModelID(id, canonicalID: "qwen3-omni-30b-a3b-thinking")
        let isQwen3ASR4B = isFireworksModelID(id, canonicalID: "qwen3-asr-4b")
        let isQwen3ASR06B = isFireworksModelID(id, canonicalID: "qwen3-asr-0.6b")

        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?
        var contextWindow = 128000
        var name = id

        // Known models we explicitly support well.
        if isQwen3OmniInstruct || isQwen3OmniThinking {
            caps.insert(.vision)
            caps.insert(.audio)
        } else if isQwen3ASR4B || isQwen3ASR06B {
            caps.insert(.audio)
        } else if isKimiK2p5 {
            caps.insert(.vision)
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks model page advertises 262.1k tokens.
            contextWindow = 262_100
            name = "Kimi K2.5"
        } else if isMiniMaxM2p5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks docs advertise 204,800 tokens.
            contextWindow = 204_800
            name = "MiniMax M2.5"
        } else if isMiniMaxM2p1 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks model page advertises 204.8k tokens.
            contextWindow = 204_800
            name = "MiniMax M2.1"
        } else if isMiniMaxM2 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks model page advertises 196.6k tokens.
            contextWindow = 196_600
            name = "MiniMax M2"
        } else if isGLM5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks model page advertises 202.8k tokens.
            contextWindow = 202_800
            name = "GLM-5"
        } else if isGLM4p7 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Fireworks model page advertises 202.8k tokens.
            contextWindow = 202_800
            name = "GLM-4.7"
        } else if isFireworksMiniMaxM2FamilyModel(id) {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 204_800
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    private func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
        fireworksCanonicalModelID(modelID)?.hasPrefix("minimax-m2") == true
    }

    private func fireworksCanonicalModelID(_ modelID: String) -> String? {
        let lower = modelID.lowercased()
        if lower.hasPrefix("fireworks/") {
            return String(lower.dropFirst("fireworks/".count))
        }
        if lower.hasPrefix("accounts/fireworks/models/") {
            return String(lower.dropFirst("accounts/fireworks/models/".count))
        }
        if !lower.contains("/") {
            return lower
        }
        return nil
    }
}
