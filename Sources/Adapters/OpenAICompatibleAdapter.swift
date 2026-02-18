import Foundation

/// Generic OpenAI-compatible provider adapter (Chat Completions API).
///
/// Expected endpoints:
/// - GET  /models
/// - POST /chat/completions
actor OpenAICompatibleAdapter: LLMProviderAdapter {
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
        if providerConfig.type == .mistral, isMistralTranscriptionOnlyModelID(modelID.lowercased()) {
            throw LLMError.invalidRequest(
                message: "Model \(modelID) is transcription-only on Mistral /v1/audio/transcriptions. Use voxtral-mini-latest or voxtral-small-latest for chat."
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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? providerConfig.type.defaultBaseURL ?? "https://api.openai.com/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v1"
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

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = resolvedRequestShape(for: modelID)
        let shouldOmitSamplingControls = applyReasoning(
            to: &body,
            controls: controls,
            modelID: modelID,
            requestShape: requestShape
        )

        if !shouldOmitSamplingControls {
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
            if hasRichUserContent {
                dict["content"] = translateUserContentParts(message.content)
            } else {
                dict["content"] = visibleContent
            }

        case .tool:
            dict["content"] = visibleContent
        }

        return dict
    }

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, thinking: String?, hasRichUserContent: Bool) {
        var visibleSegments: [String] = []
        var thinkingSegments: [String] = []
        var hasRichUserContent = false

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
            case .redactedThinking, .video:
                continue
            case .image:
                hasRichUserContent = true
            case .audio:
                hasRichUserContent = true
            }
        }

        let visible = visibleSegments.joined(separator: "\n")
        let thinking = thinkingSegments.isEmpty ? nil : thinkingSegments.joined(separator: "\n")
        return (visible, thinking, hasRichUserContent)
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

        // Mistral Voxtral expects a raw base64 string for `input_audio`.
        if providerConfig.type == .mistral {
            return [
                "type": "input_audio",
                "input_audio": payloadData.base64EncodedString()
            ]
        }

        guard let format = openAIInputAudioFormat(mimeType: audio.mimeType) else {
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

    private func mapReasoningEffort(
        _ effort: ReasoningEffort,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> String {
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
            if (requestShape == .openAIResponses || requestShape == .openAICompatible),
               ModelCapabilityRegistry.supportsOpenAIStyleExtremeEffort(
                for: providerConfig.type,
                modelID: modelID
               ) {
                return "xhigh"
            }
            return "high"
        }
    }

    private func resolvedRequestShape(for modelID: String) -> ModelRequestShape {
        ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
    }

    private func configuredModel(for modelID: String) -> ModelInfo? {
        if let exact = providerConfig.models.first(where: { $0.id == modelID }) {
            return exact
        }
        let target = modelID.lowercased()
        return providerConfig.models.first(where: { $0.id.lowercased() == target })
    }

    private func modelSupportsReasoning(for modelID: String) -> Bool {
        guard let model = configuredModel(for: modelID) else {
            // Conservative fallback: only enable reasoning when model-name rules identify it.
            return ModelCapabilityRegistry.defaultReasoningConfig(
                for: providerConfig.type,
                modelID: modelID
            ) != nil
        }

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
        guard resolved.capabilities.contains(.reasoning) else { return false }
        guard let reasoningConfig = resolved.reasoningConfig else { return false }
        return reasoningConfig.type != .none
    }

    /// Returns true when temperature/top_p should be omitted for compatibility.
    private func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        guard modelSupportsReasoning(for: modelID) else { return false }
        guard let reasoning = controls.reasoning else { return false }

        switch requestShape {
        case .openAIResponses, .openAICompatible:
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                body["reasoning"] = ["effort": "none"]
                return false
            }

            let effort = reasoning.effort ?? .medium
            body["reasoning"] = [
                "effort": mapReasoningEffort(
                    effort,
                    modelID: modelID,
                    requestShape: requestShape
                )
            ]
            return requestShape == .openAIResponses

        case .anthropic:
            guard reasoning.enabled else { return false }

            if let budget = reasoning.budgetTokens {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": budget
                ]
            } else {
                body["thinking"] = ["type": "adaptive"]
                if let effort = reasoning.effort {
                    mergeOutputConfig(
                        into: &body,
                        additional: ["effort": mapAnthropicEffort(effort)]
                    )
                }
            }

            return true

        case .gemini:
            var thinkingConfig: [String: Any] = [:]
            if reasoning.enabled {
                thinkingConfig["includeThoughts"] = true
                if let effort = reasoning.effort {
                    thinkingConfig["thinkingLevel"] = mapGeminiThinkingLevel(effort)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }
            } else {
                thinkingConfig["thinkingLevel"] = "MINIMAL"
            }

            if !thinkingConfig.isEmpty {
                var generationConfig = body["generationConfig"] as? [String: Any] ?? [:]
                generationConfig["thinkingConfig"] = thinkingConfig
                body["generationConfig"] = generationConfig
            }

            return false

        }
    }

    private func mapAnthropicEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "max"
        }
    }

    private func mapGeminiThinkingLevel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal:
            return "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return "MEDIUM"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    private func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        var merged = (body["output_config"] as? [String: Any]) ?? [:]
        for (key, value) in additional {
            merged[key] = value
        }
        body["output_config"] = merged
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = [.streaming, .toolCalling]
        let reasoningConfig = ModelCapabilityRegistry.defaultReasoningConfig(for: providerConfig.type, modelID: id)
        let contextWindow = 128000

        if reasoningConfig != nil {
            caps.insert(.reasoning)
        }

        if lower.contains("vision") || lower.contains("image") || lower.contains("gpt-4o") || lower.contains("gpt-5") || lower.contains("gemini") || lower.contains("claude") {
            caps.insert(.vision)
        }

        if lower.contains("image") {
            caps.insert(.imageGeneration)
        }

        if supportsAudioInputModelID(lower) {
            caps.insert(.audio)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        if lowerModelID.contains("gpt-audio")
            || lowerModelID.contains("audio-preview")
            || lowerModelID.contains("realtime")
            || lowerModelID.contains("qwen3-asr")
            || lowerModelID.contains("qwen3-omni") {
            return true
        }

        if lowerModelID.contains("voxtral") && !isMistralTranscriptionOnlyModelID(lowerModelID) {
            return true
        }

        if (lowerModelID.contains("gemini-2.5") || lowerModelID.contains("gemini-3") || lowerModelID.contains("gemini-2.0"))
            && !lowerModelID.contains("-image")
            && !lowerModelID.contains("imagen") {
            return true
        }

        return false
    }

    private func isMistralTranscriptionOnlyModelID(_ lowerModelID: String) -> Bool {
        lowerModelID == "voxtral-mini-2602" || lowerModelID.contains("transcribe")
    }
}
