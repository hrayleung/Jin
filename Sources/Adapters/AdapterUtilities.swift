import Foundation

// MARK: - URL Validation

/// Constructs a URL from a string, throwing `LLMError.invalidRequest` instead of crashing
/// on malformed input. Use this instead of `URL(string:)!` everywhere a provider base URL
/// or user-configurable endpoint is interpolated.
func validatedURL(_ string: String) throws -> URL {
    guard let url = URL(string: string),
          let scheme = url.scheme?.lowercased(),
          let host = url.host,
          !host.isEmpty else {
        throw LLMError.invalidRequest(
            message: "Invalid URL (must be absolute with http/https/ws/wss): \(string)"
        )
    }

    guard scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss" else {
        throw LLMError.invalidRequest(
            message: "Invalid URL scheme '\(scheme)' (expected http/https/ws/wss): \(string)"
        )
    }

    return url
}

// MARK: - String Normalization

/// Returns a trimmed, non-empty string or nil. Used across adapters to normalize
/// optional string fields (cache keys, conversation IDs, etc.) before sending to providers.
func normalizedTrimmedString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - JSON Encoding / Decoding

/// Encodes a dictionary of `AnyCodable` values to a JSON string.
/// Returns `"{}"` if encoding fails.
func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
    let raw = object.mapValues { $0.value }
    guard JSONSerialization.isValidJSONObject(raw),
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}

/// Parses a JSON string into a dictionary of `AnyCodable` values.
/// Returns an empty dictionary if parsing fails.
func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
    guard let data = jsonString.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object.mapValues(AnyCodable.init)
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
    translateNonToolMessage: (Message) -> [String: Any]
) -> [[String: Any]] {
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

// MARK: - Image URL Encoding

/// Converts an `ImageContent` to a data URI or remote URL string.
/// Shared by adapters that support vision (OpenAICompatible, OpenRouter, Fireworks, Perplexity).
func imageToURLString(_ image: ImageContent) -> String? {
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

// MARK: - Audio Input Encoding

/// Resolves the raw audio data from an `AudioContent`, reading from disk if needed.
func resolveAudioData(_ audio: AudioContent) -> Data? {
    if let data = audio.data {
        return data
    }
    if let url = audio.url, url.isFileURL {
        return try? Data(contentsOf: url)
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
func openAIInputAudioPart(_ audio: AudioContent) -> [String: Any]? {
    guard let payloadData = resolveAudioData(audio),
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
        thinking: thinkingParts.joined(separator: separator),
        hasRichUserContent: hasRichUserContent
    )
}

// MARK: - User Content Part Translation

/// Translates user content parts to the OpenAI multimodal content format.
/// Used by adapters that support vision and/or audio input.
func translateUserContentPartsToOpenAIFormat(
    _ parts: [ContentPart],
    audioPartBuilder: ((AudioContent) -> [String: Any]?)? = openAIInputAudioPart
) -> [[String: Any]] {
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
            if let urlString = imageToURLString(image) {
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
            if let builder = audioPartBuilder, let inputAudio = builder(audio) {
                out.append(inputAudio)
            }

        case .thinking, .redactedThinking, .video:
            continue
        }
    }

    return out
}

// MARK: - Model Lookup

/// Finds a model in the provider config by ID (case-insensitive fallback).
func findConfiguredModel(in providerConfig: ProviderConfig, for modelID: String) -> ModelInfo? {
    if let exact = providerConfig.models.first(where: { $0.id == modelID }) {
        return exact
    }
    let target = modelID.lowercased()
    return providerConfig.models.first(where: { $0.id.lowercased() == target })
}

// MARK: - Reasoning Support Detection

/// Checks whether a model supports reasoning based on configured model info or capability registry.
func modelSupportsReasoning(
    providerConfig: ProviderConfig,
    modelID: String
) -> Bool {
    guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
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

// MARK: - Base URL Normalization

/// Strips a trailing `/v1` suffix from a base URL, returning the root.
/// Useful for providers where users may paste a URL with or without the version path.
func stripTrailingV1(_ rawURL: String) -> String {
    let trimmed = rawURL.hasSuffix("/") ? String(rawURL.dropLast()) : rawURL

    if trimmed.hasSuffix("/v1") {
        let withoutV1 = String(trimmed.dropLast(3))
        return withoutV1.hasSuffix("/") ? String(withoutV1.dropLast()) : withoutV1
    }

    return trimmed
}
