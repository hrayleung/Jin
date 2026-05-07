import Foundation

extension OpenCodeGoAdapter {
    static func isAnthropicModel(_ modelID: String) -> Bool {
        anthropicModelIDs.contains(modelID.lowercased())
    }

    func buildOpenAIRequest(
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

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none {
                body["reasoning"] = ["effort": "none"]
            } else if let effort = reasoning.effort {
                body["reasoning"] = ["effort": mapReasoningEffort(effort)]
            }
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true,
           ModelCapabilityRegistry.supportsWebSearch(for: providerConfig.type, modelID: modelID) {
            toolObjects.append(buildWebSearchTool(from: controls.webSearch))
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

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(Self.hardcodedBaseURL)/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
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
            dict["content"] = split.visible
        }

        return dict
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

    private func buildWebSearchTool(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "web_search"]

        if let limit = controls?.maxUses, limit > 0 {
            tool["limit"] = limit
        }

        if let location = controls?.userLocation,
           let userLocation = buildUserLocation(location) {
            tool["user_location"] = userLocation
        }

        return tool
    }

    private func buildUserLocation(_ location: WebSearchUserLocation) -> [String: Any]? {
        var userLocation: [String: Any] = ["type": "approximate"]

        if let country = normalizedWebSearchLocationField(location.country) {
            userLocation["country"] = country
        }
        if let region = normalizedWebSearchLocationField(location.region) {
            userLocation["region"] = region
        }
        if let city = normalizedWebSearchLocationField(location.city) {
            userLocation["city"] = city
        }

        return userLocation.count > 1 ? userLocation : nil
    }

    private func normalizedWebSearchLocationField(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }
}
