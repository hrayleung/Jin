import Foundation

// MARK: - OpenAI Image Generation

/// OpenAI image-generation controls (`/v1/images/generations` + `/v1/images/edits`).
///
/// Supports `gpt-image-1`, `gpt-image-1.5`, `gpt-image-1-mini`, `dall-e-3`, and `dall-e-2`.
struct OpenAIImageGenerationControls: Codable {
    var count: Int?
    var size: OpenAIImageSize?
    var quality: OpenAIImageQuality?
    var style: OpenAIImageStyle?
    var background: OpenAIImageBackground?
    var outputFormat: OpenAIImageOutputFormat?
    var outputCompression: Int?
    var moderation: OpenAIImageModeration?
    /// Controls how closely the model matches input image style/features (gpt-image-1 only).
    var inputFidelity: OpenAIImageInputFidelity?
    var user: String?

    init(
        count: Int? = nil,
        size: OpenAIImageSize? = nil,
        quality: OpenAIImageQuality? = nil,
        style: OpenAIImageStyle? = nil,
        background: OpenAIImageBackground? = nil,
        outputFormat: OpenAIImageOutputFormat? = nil,
        outputCompression: Int? = nil,
        moderation: OpenAIImageModeration? = nil,
        inputFidelity: OpenAIImageInputFidelity? = nil,
        user: String? = nil
    ) {
        self.count = count
        self.size = size
        self.quality = quality
        self.style = style
        self.background = background
        self.outputFormat = outputFormat
        self.outputCompression = outputCompression
        self.moderation = moderation
        self.inputFidelity = inputFidelity
        self.user = user
    }

    var isEmpty: Bool {
        count == nil
            && size == nil
            && quality == nil
            && style == nil
            && background == nil
            && outputFormat == nil
            && outputCompression == nil
            && moderation == nil
            && inputFidelity == nil
            && (user?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// Supported image sizes.
///
/// GPT image models: `1024x1024`, `1536x1024`, `1024x1536`, `auto`.
/// DALL-E 3: `1024x1024`, `1792x1024`, `1024x1792`.
/// DALL-E 2: `256x256`, `512x512`, `1024x1024`.
enum OpenAIImageSize: String, Codable, CaseIterable {
    case auto
    case size1024x1024 = "1024x1024"
    case size1536x1024 = "1536x1024"
    case size1024x1536 = "1024x1536"
    case size1792x1024 = "1792x1024"
    case size1024x1792 = "1024x1792"
    case size512x512 = "512x512"
    case size256x256 = "256x256"

    var displayName: String { rawValue }

    /// Sizes supported by GPT Image models (gpt-image-1, gpt-image-1.5, gpt-image-1-mini).
    static let gptImageSizes: [OpenAIImageSize] = [
        .auto, .size1024x1024, .size1536x1024, .size1024x1536,
    ]

    /// Sizes supported by DALL-E 3.
    static let dallE3Sizes: [OpenAIImageSize] = [
        .size1024x1024, .size1792x1024, .size1024x1792,
    ]

    /// Sizes supported by DALL-E 2.
    static let dallE2Sizes: [OpenAIImageSize] = [
        .size256x256, .size512x512, .size1024x1024,
    ]
}

/// Image quality.
///
/// GPT image models: `low`, `medium`, `high`, `auto`.
/// DALL-E 3: `standard`, `hd`.
/// DALL-E 2: `standard` only.
enum OpenAIImageQuality: String, Codable, CaseIterable {
    case auto
    case low
    case medium
    case high
    case standard
    case hd

    var displayName: String {
        switch self {
        case .hd: return "HD"
        default: return rawValue.capitalized
        }
    }

    /// Quality options for GPT Image models.
    static let gptImageQualities: [OpenAIImageQuality] = [.auto, .low, .medium, .high]

    /// Quality options for DALL-E 3.
    static let dallE3Qualities: [OpenAIImageQuality] = [.standard, .hd]
}

/// Image style (DALL-E 3 only).
enum OpenAIImageStyle: String, Codable, CaseIterable {
    case vivid
    case natural

    var displayName: String { rawValue.capitalized }
}

/// Background transparency control (GPT image models only).
///
/// `transparent` requires `png` or `webp` output format.
enum OpenAIImageBackground: String, Codable, CaseIterable {
    case auto
    case transparent
    case opaque

    var displayName: String { rawValue.capitalized }
}

/// Output format (GPT image models only).
enum OpenAIImageOutputFormat: String, Codable, CaseIterable {
    case png
    case jpeg
    case webp

    var displayName: String { rawValue.uppercased() }

    var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .webp: return "image/webp"
        }
    }
}

/// Content moderation strictness (GPT image models only).
enum OpenAIImageModeration: String, Codable, CaseIterable {
    case auto
    case low

    var displayName: String { rawValue.capitalized }
}

/// Input fidelity for image edits (gpt-image-1 only).
///
/// Controls how much effort the model exerts to match the style and features
/// (especially facial features) of input images.
enum OpenAIImageInputFidelity: String, Codable, CaseIterable {
    case low
    case high

    var displayName: String { rawValue.capitalized }
}
