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

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningContent,
            networkManager: networkManager
        )
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
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateToolToOpenAIFormat)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://api.fireworks.ai/inference/v1")
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
        var request = URLRequest(url: try validatedURL("\(baseURL)/chat/completions"))
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
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: fireworksInputAudioPart
                )
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if split.visible.isEmpty {
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = split.visible
            }

            if !split.thinking.isEmpty {
                dict["reasoning_content"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    // MARK: - Fireworks Audio

    private func fireworksInputAudioPart(_ audio: AudioContent) -> [String: Any]? {
        guard let payloadData = resolveAudioData(audio) else {
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

    // MARK: - Reasoning

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

    // MARK: - Model Info

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

        if isQwen3OmniInstruct || isQwen3OmniThinking {
            caps.insert(.vision)
            caps.insert(.audio)
        } else if isQwen3ASR4B || isQwen3ASR06B {
            caps.insert(.audio)
        } else if isKimiK2p5 {
            caps.insert(.vision)
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 262_100
            name = "Kimi K2.5"
        } else if isMiniMaxM2p5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 196_600
            name = "MiniMax M2.5"
        } else if isMiniMaxM2p1 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 204_800
            name = "MiniMax M2.1"
        } else if isMiniMaxM2 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 196_600
            name = "MiniMax M2"
        } else if isGLM5 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 202_800
            name = "GLM-5"
        } else if isGLM4p7 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            contextWindow = 202_800
            name = "GLM-4.7"
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    // MARK: - Model ID Matching

    private func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    private func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
        guard let canonical = fireworksCanonicalModelID(modelID) else { return false }
        return canonical == "minimax-m2" || canonical == "minimax-m2p1" || canonical == "minimax-m2p5"
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
