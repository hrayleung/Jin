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
    case res1080p = "1080p"

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
    private static let seedanceModelIDs: Set<String> = [
        "bytedance/seedance-1-5-pro",
        "bytedance/seedance-2.0",
        "bytedance/seedance-2.0-fast",
    ]

    static let genericAspectRatios: [OpenRouterVideoAspectRatio] = [
        .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9, .ratio9x21,
    ]

    static func supportedDurations(for modelID: String) -> [Int] {
        switch modelID.lowercased() {
        case "bytedance/seedance-1-5-pro":
            return Array(4...12)
        case "bytedance/seedance-2.0", "bytedance/seedance-2.0-fast":
            return Array(4...15)
        default:
            return [4, 6, 8, 10, 12]
        }
    }

    static func supportedAspectRatios(for modelID: String) -> [OpenRouterVideoAspectRatio] {
        let lower = modelID.lowercased()
        if seedanceModelIDs.contains(lower) {
            return genericAspectRatios
        }
        return genericAspectRatios
    }

    static func supportedResolutions(for modelID: String) -> [OpenRouterVideoResolution] {
        switch modelID.lowercased() {
        case "bytedance/seedance-1-5-pro":
            return [.res480p, .res720p, .res1080p]
        case "bytedance/seedance-2.0", "bytedance/seedance-2.0-fast":
            return [.res480p, .res720p]
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
        switch modelID.lowercased() {
        case "bytedance/seedance-1-5-pro", "bytedance/seedance-2.0", "bytedance/seedance-2.0-fast":
            return "seed"
        default:
            return nil
        }
    }
}
