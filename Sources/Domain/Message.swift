import Foundation

/// Role of a message in the conversation
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

/// Content part supporting multimodal messages
enum ContentPart: Codable, Sendable {
    case text(String)
    case quote(QuoteContent)
    case image(ImageContent)
    case video(VideoContent)
    case file(FileContent)
    case audio(AudioContent)
    case thinking(ThinkingBlock) // Reasoning output
    case redactedThinking(RedactedThinkingBlock) // Provider-redacted reasoning output

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case quote
        case image
        case video
        case file
        case audio
        case thinking
        case signature
        case redactedData
        case provider
    }

    enum ContentType: String, Codable {
        case text
        case quote
        case image
        case video
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
        case .quote:
            let quote = try container.decode(QuoteContent.self, forKey: .quote)
            self = .quote(quote)
        case .image:
            let image = try container.decode(ImageContent.self, forKey: .image)
            self = .image(image)
        case .video:
            let video = try container.decode(VideoContent.self, forKey: .video)
            self = .video(video)
        case .file:
            let file = try container.decode(FileContent.self, forKey: .file)
            self = .file(file)
        case .audio:
            let audio = try container.decode(AudioContent.self, forKey: .audio)
            self = .audio(audio)
        case .thinking:
            let text = try container.decode(String.self, forKey: .thinking)
            let signature = try container.decodeIfPresent(String.self, forKey: .signature)
            let provider = try container.decodeIfPresent(String.self, forKey: .provider)
            self = .thinking(ThinkingBlock(text: text, signature: signature, provider: provider))
        case .redactedThinking:
            let data = try container.decode(String.self, forKey: .redactedData)
            let provider = try container.decodeIfPresent(String.self, forKey: .provider)
            self = .redactedThinking(RedactedThinkingBlock(data: data, provider: provider))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .quote(let quote):
            try container.encode(ContentType.quote, forKey: .type)
            try container.encode(quote, forKey: .quote)
        case .image(let image):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(image, forKey: .image)
        case .video(let video):
            try container.encode(ContentType.video, forKey: .type)
            try container.encode(video, forKey: .video)
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
            try container.encodeIfPresent(thinking.provider, forKey: .provider)
        case .redactedThinking(let thinking):
            try container.encode(ContentType.redactedThinking, forKey: .type)
            try container.encode(thinking.data, forKey: .redactedData)
            try container.encodeIfPresent(thinking.provider, forKey: .provider)
        }
    }
}

/// Provider reasoning block (e.g., OpenAI reasoning text; Anthropic thinking block with signature)
struct ThinkingBlock: Codable, Sendable {
    let text: String
    let signature: String?
    /// The provider type that originated this thinking block (e.g. "anthropic", "gemini").
    /// Used to filter out foreign thinking blocks when sending to a specific provider.
    let provider: String?

    init(text: String, signature: String? = nil, provider: String? = nil) {
        self.text = text
        self.signature = signature
        self.provider = provider
    }
}

/// Provider-redacted reasoning block (e.g., Anthropic redacted_thinking)
struct RedactedThinkingBlock: Codable, Sendable {
    let data: String
    /// The provider type that originated this block.
    let provider: String?

    init(data: String, provider: String? = nil) {
        self.data = data
        self.provider = provider
    }
}

enum MediaAssetDisposition: String, Codable, Equatable, Sendable {
    case managed
    case externalReference
}

private func inferredMediaAssetDisposition(data: Data?, url: URL?) -> MediaAssetDisposition {
    if data != nil || url?.isFileURL == true {
        return .managed
    }
    if url != nil {
        return .externalReference
    }
    return .managed
}

/// Image content with in-memory data, a local attachment URL, or an external remote URL.
struct ImageContent: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case mimeType
        case data
        case url
        case assetDisposition
    }

    let mimeType: String // image/jpeg, image/png, image/webp
    let data: Data?
    let url: URL?
    let assetDisposition: MediaAssetDisposition

    var remoteURL: URL? {
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    init(
        mimeType: String,
        data: Data? = nil,
        url: URL? = nil,
        assetDisposition: MediaAssetDisposition? = nil
    ) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
        self.assetDisposition = assetDisposition ?? inferredMediaAssetDisposition(data: data, url: url)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try container.decode(String.self, forKey: .mimeType)
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let assetDisposition = try container.decodeIfPresent(MediaAssetDisposition.self, forKey: .assetDisposition)

        self.init(mimeType: mimeType, data: data, url: url, assetDisposition: assetDisposition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(assetDisposition, forKey: .assetDisposition)
    }
}

/// Video content with in-memory data, a local attachment URL, or an external remote URL.
struct VideoContent: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case mimeType
        case data
        case url
        case assetDisposition
    }

    let mimeType: String // video/mp4, video/webm
    let data: Data?
    let url: URL?
    let assetDisposition: MediaAssetDisposition

    var remoteURL: URL? {
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    init(
        mimeType: String,
        data: Data? = nil,
        url: URL? = nil,
        assetDisposition: MediaAssetDisposition? = nil
    ) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
        self.assetDisposition = assetDisposition ?? inferredMediaAssetDisposition(data: data, url: url)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try container.decode(String.self, forKey: .mimeType)
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let assetDisposition = try container.decodeIfPresent(MediaAssetDisposition.self, forKey: .assetDisposition)

        self.init(mimeType: mimeType, data: data, url: url, assetDisposition: assetDisposition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(assetDisposition, forKey: .assetDisposition)
    }
}

/// File content (PDFs, documents)
struct FileContent: Codable, Sendable {
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
struct AudioContent: Codable, Sendable {
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
struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: [ContentPart]
    let toolCalls: [ToolCall]?
    let toolResults: [ToolResult]?
    let searchActivities: [SearchActivity]?
    let codeExecutionActivities: [CodeExecutionActivity]?
    let codexToolActivities: [CodexToolActivity]?
    let agentToolActivities: [CodexToolActivity]?
    let timestamp: Date
    /// MCP server names selected via slash command for this specific message.
    let perMessageMCPServerNames: [String]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [ContentPart],
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        searchActivities: [SearchActivity]? = nil,
        codeExecutionActivities: [CodeExecutionActivity]? = nil,
        codexToolActivities: [CodexToolActivity]? = nil,
        agentToolActivities: [CodexToolActivity]? = nil,
        timestamp: Date = Date(),
        perMessageMCPServerNames: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.searchActivities = searchActivities
        self.codeExecutionActivities = codeExecutionActivities
        self.codexToolActivities = codexToolActivities
        self.agentToolActivities = agentToolActivities
        self.timestamp = timestamp
        self.perMessageMCPServerNames = perMessageMCPServerNames
    }
}

/// Tool call from LLM
struct ToolCall: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]
    let signature: String?
    let providerContext: [String: String]?

    init(
        id: String,
        name: String,
        arguments: [String: AnyCodable],
        signature: String? = nil,
        providerContext: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.signature = signature
        self.providerContext = providerContext
    }

    func providerContextValue(for key: String) -> String? {
        providerContext?[key]
    }
}

/// Result from tool execution
struct ToolResult: Codable, Identifiable, Sendable {
    let id: String
    let toolCallID: String
    let toolName: String?
    let content: String
    let isError: Bool
    let signature: String?
    let durationSeconds: Double?
    let rawOutputPath: String?

    init(
        id: String = UUID().uuidString,
        toolCallID: String,
        toolName: String? = nil,
        content: String,
        isError: Bool = false,
        signature: String? = nil,
        durationSeconds: Double? = nil,
        rawOutputPath: String? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.content = content
        self.isError = isError
        self.signature = signature
        self.durationSeconds = durationSeconds
        self.rawOutputPath = rawOutputPath
    }
}

/// Normalized provider-native web-search activity.
struct SearchActivity: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let status: SearchActivityStatus
    let arguments: [String: AnyCodable]
    let outputIndex: Int?
    let sequenceNumber: Int?

    init(
        id: String,
        type: String,
        status: SearchActivityStatus,
        arguments: [String: AnyCodable] = [:],
        outputIndex: Int? = nil,
        sequenceNumber: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.arguments = arguments
        self.outputIndex = outputIndex
        self.sequenceNumber = sequenceNumber
    }

    func merged(with newer: SearchActivity) -> SearchActivity {
        SearchActivity(
            id: id,
            type: newer.type.isEmpty ? type : newer.type,
            status: newer.status,
            arguments: arguments.merging(newer.arguments) { _, new in new },
            outputIndex: newer.outputIndex ?? outputIndex,
            sequenceNumber: newer.sequenceNumber ?? sequenceNumber
        )
    }
}

/// Status for provider-native web-search activity.
enum SearchActivityStatus: Codable, Sendable, Equatable {
    case inProgress
    case searching
    case completed
    case failed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "in_progress":
            self = .inProgress
        case "searching":
            self = .searching
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .inProgress:
            return "in_progress"
        case .searching:
            return "searching"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = SearchActivityStatus(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Type-erased codable value
// Stores JSON-compatible value graphs (null/bool/number/string/array/object).
// Marked unchecked because the erased `Any` payload cannot be proven at compile time.
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
            return
        }

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
        case is NSNull:
            try container.encodeNil()
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
