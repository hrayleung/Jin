import Foundation

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
