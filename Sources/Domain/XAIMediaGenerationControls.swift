import Foundation

// MARK: - xAI Image Generation

/// xAI image-generation controls (`/images/generations` + `/images/edits`).
struct XAIImageGenerationControls: Codable {
    var count: Int?
    var aspectRatio: XAIAspectRatio?
    /// Deprecated: kept for backwards compatibility with older persisted controls.
    var size: XAIImageSize?
    /// Deprecated: currently unsupported by xAI image APIs.
    var quality: XAIImageQuality?
    /// Deprecated: currently unsupported by xAI image APIs.
    var style: XAIImageStyle?
    var user: String?

    init(
        count: Int? = nil,
        aspectRatio: XAIAspectRatio? = nil,
        size: XAIImageSize? = nil,
        quality: XAIImageQuality? = nil,
        style: XAIImageStyle? = nil,
        user: String? = nil
    ) {
        self.count = count
        self.aspectRatio = aspectRatio
        self.size = size
        self.quality = quality
        self.style = style
        self.user = user
    }

    var isEmpty: Bool {
        count == nil
            && aspectRatio == nil
            && size == nil
            && quality == nil
            && style == nil
            && (user?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum XAIAspectRatio: String, Codable, CaseIterable {
    case ratio1x1 = "1:1"
    case ratio3x4 = "3:4"
    case ratio4x3 = "4:3"
    case ratio9x16 = "9:16"
    case ratio16x9 = "16:9"
    case ratio2x3 = "2:3"
    case ratio3x2 = "3:2"
    case ratio4x5 = "4:5"
    case ratio5x4 = "5:4"

    var displayName: String { rawValue }
}

enum XAIImageSize: String, Codable, CaseIterable {
    case size1024x1024 = "1024x1024"
    case size1536x1024 = "1536x1024"
    case size1024x1536 = "1024x1536"
    case auto

    var displayName: String { rawValue }

    /// Older size controls map cleanly onto supported xAI aspect ratios.
    var mappedAspectRatio: XAIAspectRatio? {
        switch self {
        case .size1024x1024: return .ratio1x1
        case .size1536x1024: return .ratio3x2
        case .size1024x1536: return .ratio2x3
        case .auto: return nil
        }
    }
}

enum XAIImageQuality: String, Codable, CaseIterable {
    case low, medium, high, auto

    var displayName: String { rawValue.capitalized }
}

enum XAIImageStyle: String, Codable, CaseIterable {
    case natural, vivid

    var displayName: String { rawValue.capitalized }
}

// MARK: - xAI Video Generation

/// xAI video-generation controls (`/v1/videos/generations`).
struct XAIVideoGenerationControls: Codable {
    var duration: Int?
    var aspectRatio: XAIAspectRatio?
    var resolution: XAIVideoResolution?

    init(
        duration: Int? = nil,
        aspectRatio: XAIAspectRatio? = nil,
        resolution: XAIVideoResolution? = nil
    ) {
        self.duration = duration
        self.aspectRatio = aspectRatio
        self.resolution = resolution
    }

    var isEmpty: Bool {
        duration == nil && aspectRatio == nil && resolution == nil
    }
}

enum XAIVideoResolution: String, Codable, CaseIterable {
    case res480p = "480p"
    case res720p = "720p"

    var displayName: String { rawValue }
}
