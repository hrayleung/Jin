import Foundation

/// Role of a message in the conversation
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

/// Content part supporting multimodal messages
enum ContentPart: Codable {
    case text(String)
    case image(ImageContent)
    case file(FileContent)
    case audio(AudioContent)
    case thinking(ThinkingBlock) // Reasoning output
    case redactedThinking(RedactedThinkingBlock) // Provider-redacted reasoning output

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case image
        case file
        case audio
        case thinking
        case signature
        case redactedData
    }

    enum ContentType: String, Codable {
        case text
        case image
        case file
        case audio
        case thinking
        case redactedThinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)

        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case .image:
            let image = try container.decode(ImageContent.self, forKey: .image)
            self = .image(image)
        case .file:
            let file = try container.decode(FileContent.self, forKey: .file)
            self = .file(file)
        case .audio:
            let audio = try container.decode(AudioContent.self, forKey: .audio)
            self = .audio(audio)
        case .thinking:
            let text = try container.decode(String.self, forKey: .thinking)
            let signature = try container.decodeIfPresent(String.self, forKey: .signature)
            self = .thinking(ThinkingBlock(text: text, signature: signature))
        case .redactedThinking:
            let data = try container.decode(String.self, forKey: .redactedData)
            self = .redactedThinking(RedactedThinkingBlock(data: data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(image, forKey: .image)
        case .file(let file):
            try container.encode(ContentType.file, forKey: .type)
            try container.encode(file, forKey: .file)
        case .audio(let audio):
            try container.encode(ContentType.audio, forKey: .type)
            try container.encode(audio, forKey: .audio)
        case .thinking(let thinking):
            try container.encode(ContentType.thinking, forKey: .type)
            try container.encode(thinking.text, forKey: .thinking)
            try container.encodeIfPresent(thinking.signature, forKey: .signature)
        case .redactedThinking(let thinking):
            try container.encode(ContentType.redactedThinking, forKey: .type)
            try container.encode(thinking.data, forKey: .redactedData)
        }
    }
}

/// Provider reasoning block (e.g., OpenAI reasoning text; Anthropic thinking block with signature)
struct ThinkingBlock: Codable {
    let text: String
    let signature: String?

    init(text: String, signature: String? = nil) {
        self.text = text
        self.signature = signature
    }
}

/// Provider-redacted reasoning block (e.g., Anthropic redacted_thinking)
struct RedactedThinkingBlock: Codable {
    let data: String

    init(data: String) {
        self.data = data
    }
}

/// Image content with base64 data or URL
struct ImageContent: Codable {
    let mimeType: String // image/jpeg, image/png, image/webp
    let data: Data? // Base64 encoded
    let url: URL? // Remote URL

    init(mimeType: String, data: Data? = nil, url: URL? = nil) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
}

/// File content (PDFs, documents)
struct FileContent: Codable {
    let mimeType: String
    let filename: String
    let data: Data?
    let url: URL?
    let extractedText: String?

    init(
        mimeType: String,
        filename: String,
        data: Data? = nil,
        url: URL? = nil,
        extractedText: String? = nil
    ) {
        self.mimeType = mimeType
        self.filename = filename
        self.data = data
        self.url = url
        self.extractedText = extractedText
    }
}

/// Audio content (OpenAI only)
struct AudioContent: Codable {
    let mimeType: String // audio/mp3, audio/wav
    let data: Data?
    let url: URL?

    init(mimeType: String, data: Data? = nil, url: URL? = nil) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
}

/// Message in the conversation
struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: [ContentPart]
    let toolCalls: [ToolCall]?
    let toolResults: [ToolResult]?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [ContentPart],
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.timestamp = timestamp
    }
}

/// Tool call from LLM
struct ToolCall: Codable, Identifiable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]
    let signature: String?

    init(id: String, name: String, arguments: [String: AnyCodable], signature: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.signature = signature
    }
}

/// Result from tool execution
struct ToolResult: Codable, Identifiable {
    let id: String
    let toolCallID: String
    let toolName: String?
    let content: String
    let isError: Bool
    let signature: String?

    init(
        id: String = UUID().uuidString,
        toolCallID: String,
        toolName: String? = nil,
        content: String,
        isError: Bool = false,
        signature: String? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.content = content
        self.isError = isError
        self.signature = signature
    }
}

/// Type-erased codable value
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}
