import Foundation

/// Together AI video-generation controls (`POST /v2/videos`).
///
/// Docs:
/// - https://docs.together.ai/docs/inference/videos/overview
/// - https://docs.together.ai/docs/seedance2.0-quickstart
/// - https://docs.together.ai/reference/create-videos
/// - Model: https://www.together.ai/models/seedance-2-5 (`ByteDance/Seedance-2.5`)
struct TogetherVideoGenerationControls: Codable, Equatable {
    /// Clip length in seconds. Sent as string `seconds` on the wire.
    var durationSeconds: Int?
    var aspectRatio: TogetherVideoAspectRatio?
    var resolution: TogetherVideoResolution?
    var imageInputMode: TogetherVideoImageInputMode?
    /// Maps to Seedance `settings.audio` (default true on the provider).
    var generateAudio: Bool?
    var seed: Int?

    init(
        durationSeconds: Int? = nil,
        aspectRatio: TogetherVideoAspectRatio? = nil,
        resolution: TogetherVideoResolution? = nil,
        imageInputMode: TogetherVideoImageInputMode? = nil,
        generateAudio: Bool? = nil,
        seed: Int? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageInputMode = imageInputMode
        self.generateAudio = generateAudio
        self.seed = seed
    }

    var isEmpty: Bool {
        durationSeconds == nil
            && aspectRatio == nil
            && resolution == nil
            && imageInputMode == nil
            && generateAudio == nil
            && seed == nil
    }
}

enum TogetherVideoAspectRatio: String, Codable, CaseIterable, Equatable {
    case ratio1x1 = "1:1"
    case ratio3x4 = "3:4"
    case ratio4x3 = "4:3"
    case ratio9x16 = "9:16"
    case ratio16x9 = "16:9"
    case ratio21x9 = "21:9"

    var displayName: String { rawValue }
}

enum TogetherVideoResolution: String, Codable, CaseIterable, Equatable {
    case res480p = "480p"
    case res720p = "720p"
    case res1080p = "1080p"
    case res4k = "4k"

    var displayName: String {
        switch self {
        case .res4k: return "4K"
        default: return rawValue
        }
    }
}

enum TogetherVideoImageInputMode: String, Codable, CaseIterable, Equatable {
    case smart
    case frameImages = "frame_images"
    case referenceImages = "reference_images"

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

/// Per-model capability matrix for Together video models.
/// Source of truth: Together Seedance docs + serverless model catalog.
enum TogetherVideoModelSupport {
    /// Exact model IDs fully wired for Together video generation.
    static let seedanceModelIDs: Set<String> = [
        "bytedance/seedance-2.0",
        "bytedance/seedance-2.5",
    ]

    static func isVideoGenerationModelID(_ modelID: String) -> Bool {
        seedanceModelIDs.contains(modelID.lowercased())
    }

    /// Seedance 2.0/2.5 aspect ratios on Together (no 9:21 in official docs).
    static let seedanceAspectRatios: [TogetherVideoAspectRatio] = [
        .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9,
    ]

    static func supportedDurations(for modelID: String) -> [Int] {
        switch modelID.lowercased() {
        case "bytedance/seedance-2.0":
            // docs.together.ai/docs/seedance2.0-quickstart: integer 4...15 as string seconds
            return Array(4...15)
        case "bytedance/seedance-2.5":
            // Model page: 30-second single-pass storytelling clips.
            // API accepts every integer 4...30; curate the menu for scanability.
            return [4, 6, 8, 10, 12, 15, 20, 25, 30]
        default:
            return [4, 5, 6, 8, 10]
        }
    }

    static func supportedAspectRatios(for modelID: String) -> [TogetherVideoAspectRatio] {
        switch modelID.lowercased() {
        case "bytedance/seedance-2.0", "bytedance/seedance-2.5":
            return seedanceAspectRatios
        default:
            return seedanceAspectRatios
        }
    }

    static func supportedResolutions(for modelID: String) -> [TogetherVideoResolution] {
        switch modelID.lowercased() {
        case "bytedance/seedance-2.0":
            // Official Seedance 2.0 quickstart: 480p, 720p, 1080p, 4k
            return [.res480p, .res720p, .res1080p, .res4k]
        case "bytedance/seedance-2.5":
            // No dedicated 2.5 resolution matrix published yet; keep the conservative
            // 480p/720p tier used across Seedance 2.5 hosts until Together documents more.
            return [.res480p, .res720p]
        default:
            return [.res480p, .res720p]
        }
    }

    static func supportsAudio(for modelID: String) -> Bool {
        seedanceModelIDs.contains(modelID.lowercased())
    }
}
