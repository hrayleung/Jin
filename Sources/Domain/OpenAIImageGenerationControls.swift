import Foundation

// MARK: - OpenAI Image Generation

/// OpenAI image-generation controls (`/v1/images/generations` + `/v1/images/edits`).
///
/// Supports `gpt-image-2`, `gpt-image-1`, `gpt-image-1.5`, `gpt-image-1-mini`,
/// `dall-e-3`, and `dall-e-2`.
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
/// GPT image models: `auto` plus provider-specific presets and, for `gpt-image-2`,
/// arbitrary `WIDTHxHEIGHT` values that satisfy OpenAI's documented constraints.
/// DALL-E 3: `1024x1024`, `1792x1024`, `1024x1792`.
/// DALL-E 2: `256x256`, `512x512`, `1024x1024`.
struct OpenAIImageSize: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var displayName: String { rawValue }

    var isAuto: Bool {
        rawValue == Self.auto.rawValue
    }

    var pixelDimensions: (Int, Int)? {
        guard !isAuto else { return nil }
        let parts = rawValue.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else {
            return nil
        }
        return (width, height)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let auto = Self(rawValue: "auto")
    static let size1024x1024 = Self(rawValue: "1024x1024")
    static let size1536x1024 = Self(rawValue: "1536x1024")
    static let size1024x1536 = Self(rawValue: "1024x1536")
    static let size1792x1024 = Self(rawValue: "1792x1024")
    static let size1024x1792 = Self(rawValue: "1024x1792")
    static let size2048x2048 = Self(rawValue: "2048x2048")
    static let size2048x1152 = Self(rawValue: "2048x1152")
    static let size3840x2160 = Self(rawValue: "3840x2160")
    static let size2160x3840 = Self(rawValue: "2160x3840")
    static let size512x512 = Self(rawValue: "512x512")
    static let size256x256 = Self(rawValue: "256x256")

    /// Sizes supported by GPT Image 1 / 1.5 / 1 Mini.
    static let gptImageLegacyPresetSizes: [OpenAIImageSize] = [
        .auto, .size1024x1024, .size1536x1024, .size1024x1536,
    ]

    /// Suggested presets for GPT Image 2.
    static let gptImage2SuggestedSizes: [OpenAIImageSize] = [
        .auto,
        .size1024x1024,
        .size1536x1024,
        .size1024x1536,
        .size2048x2048,
        .size2048x1152,
        .size3840x2160,
        .size2160x3840,
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

    /// Quality options for GPT Image models, including `gpt-image-2`.
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
