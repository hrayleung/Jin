import Foundation

extension MorphLLMAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        streaming: Bool
    ) throws -> URLRequest {
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

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURLRoot)/v1/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    private func translateMessages(_ messages: [Message]) -> [[String: Any]] {
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let split = splitContentParts(message.content)
        var dict: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .system, .user:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }
}
