import Foundation

/// OpenRouter video-generation controls (`/api/v1/videos`).
struct OpenRouterVideoGenerationControls: Codable {
    var durationSeconds: Int?
    var aspectRatio: OpenRouterVideoAspectRatio?
    var resolution: OpenRouterVideoResolution?
    var imageInputMode: OpenRouterVideoImageInputMode?
    var generateAudio: Bool?
    var watermark: Bool?
    var seed: Int?

    init(
        durationSeconds: Int? = nil,
        aspectRatio: OpenRouterVideoAspectRatio? = nil,
        resolution: OpenRouterVideoResolution? = nil,
        imageInputMode: OpenRouterVideoImageInputMode? = nil,
        generateAudio: Bool? = nil,
        watermark: Bool? = nil,
        seed: Int? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageInputMode = imageInputMode
        self.generateAudio = generateAudio
        self.watermark = watermark
        self.seed = seed
    }

    var isEmpty: Bool {
        durationSeconds == nil
            && aspectRatio == nil
            && resolution == nil
            && imageInputMode == nil
            && generateAudio == nil
            && watermark == nil
            && seed == nil
    }
}

enum OpenRouterVideoAspectRatio: String, Codable, CaseIterable {
    case ratio1x1 = "1:1"
    case ratio2x3 = "2:3"
    case ratio3x2 = "3:2"
    case ratio3x4 = "3:4"
    case ratio4x3 = "4:3"
    case ratio9x16 = "9:16"
    case ratio16x9 = "16:9"
    case ratio9x21 = "9:21"
    case ratio21x9 = "21:9"

    var displayName: String { rawValue }
}

enum OpenRouterVideoResolution: String, Codable, CaseIterable {
    case res480p = "480p"
    case res720p = "720p"
    case res768p = "768p"
    case res1080p = "1080p"
    case res2K = "2K"

    var displayName: String { rawValue }
}

enum OpenRouterVideoImageInputMode: String, Codable, CaseIterable {
    case smart
    case frameImages = "frame_images"
    case referenceImages = "input_references"

    var displayName: String {
        switch self {
        case .smart:
            return "Smart"
        case .frameImages:
            return "Frame control"
        case .referenceImages:
            return "Reference images"
        }
    }
}

enum OpenRouterVideoModelSupport {
    /// Exact OpenRouter video model IDs fully wired for Seedance controls.
    /// Source of truth: GET https://openrouter.ai/api/v1/videos/models
    private static let seedanceModelIDs: Set<String> = [
        "bytedance/seedance-1-5-pro",
        "bytedance/seedance-2.0",
        "bytedance/seedance-2.0-fast",
        "bytedance/seedance-2.5",
    ]

    static let genericAspectRatios: [OpenRouterVideoAspectRatio] = [
        .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9, .ratio9x21,
    ]

    /// Seedance 2.5 omits 9:21 (OpenRouter `/videos/models` supported_aspect_ratios).
    private static let seedance25AspectRatios: [OpenRouterVideoAspectRatio] = [
        .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9,
    ]

    /// Grok Imagine Video 1.5 Lite (created 2026-10-06), per `/videos/models`:
    /// aspect ratios 16:9/9:16/1:1/4:3/3:4/3:2/2:3, resolutions 480p/720p/1080p.
    private static let grokImagineVideo15LiteAspectRatios: [OpenRouterVideoAspectRatio] = [
        .ratio1x1, .ratio2x3, .ratio3x2, .ratio3x4, .ratio4x3, .ratio9x16, .ratio16x9,
    ]

    /// HeyGen Video 1 (created 2026-09-30), per `/videos/models`:
    /// aspect ratios 21:9/16:9/4:3/1:1/3:4/9:16, resolutions 480p/768p/2K.
    private static let heygenVideo1AspectRatios: [OpenRouterVideoAspectRatio] = [
        .ratio1x1, .ratio3x4, .ratio4x3, .ratio9x16, .ratio16x9, .ratio21x9,
    ]

    static func supportedDurations(for modelID: String) -> [Int] {
        switch modelID.lowercased() {
        case "bytedance/seedance-1-5-pro":
            return Array(4...12)
        case "bytedance/seedance-2.0", "bytedance/seedance-2.0-fast":
            return Array(4...15)
        case "bytedance/seedance-2.5":
            // API accepts every integer 4...30; curate the menu for scanability.
            return [4, 6, 8, 10, 12, 15, 20, 25, 30]
        case "x-ai/grok-imagine-video-1.5-lite":
            return Array(1...15)
        case "heygen/heygen-video-1":
            return Array(5...15)
        default:
            return [4, 6, 8, 10, 12]
        }
    }

    static func supportedAspectRatios(for modelID: String) -> [OpenRouterVideoAspectRatio] {
        switch modelID.lowercased() {
        case "bytedance/seedance-2.5":
            return seedance25AspectRatios
        case "bytedance/seedance-1-5-pro",
             "bytedance/seedance-2.0",
             "bytedance/seedance-2.0-fast":
            return genericAspectRatios
        case "x-ai/grok-imagine-video-1.5-lite":
            return grokImagineVideo15LiteAspectRatios
        case "heygen/heygen-video-1":
            return heygenVideo1AspectRatios
        default:
            return genericAspectRatios
        }
    }

    static func supportedResolutions(for modelID: String) -> [OpenRouterVideoResolution] {
        switch modelID.lowercased() {
        case "bytedance/seedance-1-5-pro":
            return [.res480p, .res720p, .res1080p]
        case "bytedance/seedance-2.0":
            // OpenRouter also lists 4K; keep the enum-backed subset until 4K is added.
            return [.res480p, .res720p, .res1080p]
        case "bytedance/seedance-2.0-fast", "bytedance/seedance-2.5":
            return [.res480p, .res720p]
        case "x-ai/grok-imagine-video-1.5-lite":
            return [.res480p, .res720p, .res1080p]
        case "heygen/heygen-video-1":
            return [.res480p, .res768p, .res2K]
        default:
            return [.res480p, .res720p, .res1080p]
        }
    }

    static func supportsAudio(for modelID: String) -> Bool {
        seedanceModelIDs.contains(modelID.lowercased())
    }

    static func supportsWatermark(for modelID: String) -> Bool {
        seedanceModelIDs.contains(modelID.lowercased())
    }

    static func providerPassthroughSlug(for modelID: String) -> String? {
        seedanceModelIDs.contains(modelID.lowercased()) ? "seed" : nil
    }
}
