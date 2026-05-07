import Foundation

extension CohereAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
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

        if let topP = controls.topP {
            // Cohere uses `p` for nucleus sampling.
            body["p"] = topP
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat"),
            apiKey: apiKey,
            body: body,
            accept: streaming ? "text/event-stream" : "application/json",
            includeUserAgent: false
        )
    }

    private func translateMessages(_ messages: [Message]) -> [[String: Any]] {
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let visibleContent = renderVisibleContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue,
            "content": visibleContent
        ]

        if message.role == .assistant,
           let toolCalls = message.toolCalls,
           !toolCalls.isEmpty {
            dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
        }

        return dict
    }

    private func renderVisibleContent(_ parts: [ContentPart]) -> String {
        var segments: [String] = []
        segments.reserveCapacity(parts.count)

        for part in parts {
            switch part {
            case .text(let text):
                segments.append(text)
            case .quote(let quote):
                segments.append(quote.quotedText)
            case .file(let file):
                segments.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .image, .video, .audio, .thinking, .redactedThinking:
                continue
            }
        }

        return segments.joined(separator: "\n")
    }
}
