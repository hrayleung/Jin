import Foundation

// MARK: - Audio Input Encoding

/// Resolves the raw audio data from an `AudioContent`, reading from disk if needed.
func resolveAudioData(_ audio: AudioContent) throws -> Data? {
    if let data = audio.data {
        return data
    }
    if let url = audio.url, url.isFileURL {
        return try resolveFileData(from: url)
    }
    return nil
}

/// Maps a MIME type to the OpenAI `input_audio.format` value.
/// Returns nil for unsupported formats.
func openAIInputAudioFormat(mimeType: String) -> String? {
    let lower = mimeType.lowercased()
    if lower == "audio/wav" || lower == "audio/x-wav" {
        return "wav"
    }
    if lower == "audio/mpeg" || lower == "audio/mp3" {
        return "mp3"
    }
    return nil
}

/// Builds an OpenAI-format `input_audio` content part dictionary.
/// Returns nil if audio data cannot be resolved or format is unsupported.
func openAIInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
    guard let payloadData = try resolveAudioData(audio),
          let format = openAIInputAudioFormat(mimeType: audio.mimeType) else {
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

// MARK: - Content Splitting

/// Result of splitting `[ContentPart]` into visible text, thinking text, and
/// a flag indicating whether the message contains rich user content (images/audio).
struct SplitContentResult {
    let visible: String
    let thinking: String
    let hasRichUserContent: Bool

    var thinkingOrNil: String? {
        thinking.isEmpty ? nil : thinking
    }
}

/// Splits `[ContentPart]` into visible text, thinking text, and rich content detection.
/// This is the common pattern used across most OpenAI-compatible adapters.
///
/// - Parameters:
///   - parts: The content parts to split.
///   - separator: The string used to join visible segments (default: empty string).
///   - includeImages: Whether to detect images as rich content (default: true).
///   - includeAudio: Whether to detect audio as rich content (default: false).
///   - imageUnsupportedMessage: If non-nil, appends this message for image parts instead of
///     flagging as rich content. Used by text-only providers (DeepSeek, Cerebras).
func splitContentParts(
    _ parts: [ContentPart],
    separator: String = "",
    includeImages: Bool = true,
    includeAudio: Bool = false,
    imageUnsupportedMessage: String? = nil
) -> SplitContentResult {
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
        case .image(let image):
            if let message = imageUnsupportedMessage {
                if image.url != nil || image.data != nil {
                    visibleParts.append(message)
                }
            } else if includeImages {
                hasRichUserContent = true
            }
        case .audio:
            if includeAudio {
                hasRichUserContent = true
            }
        case .thinking(let thinking):
            if !thinking.text.isEmpty {
                thinkingParts.append(thinking.text)
            }
        case .redactedThinking, .video:
            break
        }
    }

    return SplitContentResult(
        visible: visibleParts.joined(separator: separator),
        thinking: thinkingParts.joined(),
        hasRichUserContent: hasRichUserContent
    )
}

// MARK: - User Content Part Translation

/// Translates user content parts to the OpenAI multimodal content format.
/// Used by adapters that support vision and/or audio input.
func translateUserContentPartsToOpenAIFormat(
    _ parts: [ContentPart],
    audioPartBuilder: ((AudioContent) throws -> [String: Any]?)? = openAIInputAudioPart
) throws -> [[String: Any]] {
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
            if let urlString = try imageToURLString(image) {
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
            if let builder = audioPartBuilder, let inputAudio = try builder(audio) {
                out.append(inputAudio)
            }

        case .thinking, .redactedThinking, .video:
            continue
        }
    }

    return out
}

// MARK: - OpenAI-Compatible Tool Translation

/// Translates a `ToolDefinition` into the OpenAI-compatible function calling format.
/// Used by all OpenAI-compatible adapters (DeepSeek, Cerebras, Fireworks, OpenRouter,
/// Perplexity, Cohere, OpenAICompatible).
func translateToolToOpenAIFormat(_ tool: ToolDefinition) -> [String: Any] {
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

/// Translates tool calls from domain `ToolCall` to the OpenAI-compatible wire format.
func translateToolCallsToOpenAIFormat(_ calls: [ToolCall]) -> [[String: Any]] {
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

// MARK: - OpenAI-Compatible Message Translation

/// Translates domain messages into OpenAI-compatible message format.
/// Handles tool result expansion (tool role messages are flattened inline).
/// Used by most OpenAI-compatible adapters.
func translateMessagesToOpenAIFormat(
    _ messages: [Message],
    translateNonToolMessage: (Message) throws -> [String: Any]
) rethrows -> [[String: Any]] {
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
            out.append(try translateNonToolMessage(message))

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
