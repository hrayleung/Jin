import Foundation

extension FireworksAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages),
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

        let isMiniMaxM2FamilyModel = isFireworksMiniMaxM2FamilyModel(modelID)
        let isDeepSeekV4ProModel = isFireworksDeepSeekV4ProModel(modelID)
        var deepSeekV4ProThinkingDisabled = false
        if let reasoning = controls.reasoning {
            if isDeepSeekV4ProModel {
                if reasoning.enabled == false || reasoning.effort == .some(.none) {
                    body["thinking"] = ["type": "disabled"]
                    deepSeekV4ProThinkingDisabled = true
                } else {
                    body["thinking"] = ["type": "enabled"]
                    body["reasoning_effort"] = mapDeepSeekV4ProReasoningEffort(reasoning.effort ?? .high)
                }
            } else if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none {
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
            if key == "reasoning_effort", isDeepSeekV4ProModel {
                if !deepSeekV4ProThinkingDisabled,
                   let normalized = normalizeDeepSeekV4ProReasoningEffort(value.value) {
                    body[key] = normalized
                }
                continue
            }

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

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
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

    private func fireworksInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
        guard let payloadData = try resolveAudioData(audio) else {
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

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh, .max:
            return "high"
        }
    }

    private func mapDeepSeekV4ProReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .xhigh, .max:
            return "max"
        case .none, .minimal, .low, .medium, .high:
            return "high"
        }
    }

    private func normalizeDeepSeekV4ProReasoningEffort(_ raw: Any) -> String? {
        guard let effort = raw as? String else { return nil }
        switch effort.lowercased() {
        case "max", "xhigh":
            return "max"
        case "minimal", "low", "medium", "high":
            return "high"
        default:
            return nil
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

    func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }
}
