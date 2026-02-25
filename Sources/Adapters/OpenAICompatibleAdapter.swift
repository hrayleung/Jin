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
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateToolToOpenAIFormat)
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
        var request = URLRequest(url: try validatedURL("\(baseURL)/chat/completions"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = OpenAICompatibleReasoningSupport.applyReasoning(
            to: &body,
            controls: controls,
            providerConfig: providerConfig,
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
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: true,
            includeAudio: true
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible
            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                dict["content"] = translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: mistralAudioPartBuilder
                )
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    /// Mistral Voxtral expects a raw base64 string for `input_audio`, not the standard OpenAI format.
    private func mistralAudioPartBuilder(_ audio: AudioContent) -> [String: Any]? {
        if providerConfig.type == .mistral {
            guard let payloadData = resolveAudioData(audio) else { return nil }
            return [
                "type": "input_audio",
                "input_audio": payloadData.base64EncodedString()
            ]
        }
        return openAIInputAudioPart(audio)
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
