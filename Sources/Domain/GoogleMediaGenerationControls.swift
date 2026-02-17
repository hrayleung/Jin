import Foundation

// MARK: - Google Video Generation (Veo)

/// Google Veo video-generation controls (`:predictLongRunning` polling).
struct GoogleVideoGenerationControls: Codable {
    var durationSeconds: Int?
    var aspectRatio: GoogleVideoAspectRatio?
    var resolution: GoogleVideoResolution?
    var negativePrompt: String?
    var generateAudio: Bool?
    var personGeneration: GoogleVideoPersonGeneration?
    var seed: Int?

    init(
        durationSeconds: Int? = nil,
        aspectRatio: GoogleVideoAspectRatio? = nil,
        resolution: GoogleVideoResolution? = nil,
        negativePrompt: String? = nil,
        generateAudio: Bool? = nil,
        personGeneration: GoogleVideoPersonGeneration? = nil,
        seed: Int? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.negativePrompt = negativePrompt
        self.generateAudio = generateAudio
        self.personGeneration = personGeneration
        self.seed = seed
    }

    var isEmpty: Bool {
        durationSeconds == nil
            && aspectRatio == nil
            && resolution == nil
            && (negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && generateAudio == nil
            && personGeneration == nil
            && seed == nil
    }
}

enum GoogleVideoAspectRatio: String, Codable, CaseIterable {
    case ratio16x9 = "16:9"
    case ratio9x16 = "9:16"
    case ratio1x1 = "1:1"

    var displayName: String { rawValue }
}

enum GoogleVideoResolution: String, Codable, CaseIterable {
    case res720p = "720p"
    case res1080p = "1080p"

    var displayName: String { rawValue }
}

enum GoogleVideoPersonGeneration: String, Codable, CaseIterable {
    case dontAllow = "dont_allow"
    case allowAdult = "allow_adult"
    case allowAll = "allow_all"

    var displayName: String {
        switch self {
        case .dontAllow: return "Don't allow"
        case .allowAdult: return "Allow adults"
        case .allowAll: return "Allow all"
        }
    }
}

// MARK: - Google/Gemini Image Generation

/// Image-generation controls shared by Gemini (AI Studio) and Vertex AI.
struct ImageGenerationControls: Codable {
    var responseMode: ImageResponseMode?
    var aspectRatio: ImageAspectRatio?
    /// Gemini 3 Pro Image supports 1K/2K/4K. Keep `nil` for model default.
    var imageSize: ImageOutputSize?
    var seed: Int?
    var vertexPersonGeneration: VertexImagePersonGeneration?
    var vertexOutputMIMEType: VertexImageOutputMIMEType?
    var vertexCompressionQuality: Int?

    init(
        responseMode: ImageResponseMode? = nil,
        aspectRatio: ImageAspectRatio? = nil,
        imageSize: ImageOutputSize? = nil,
        seed: Int? = nil,
        vertexPersonGeneration: VertexImagePersonGeneration? = nil,
        vertexOutputMIMEType: VertexImageOutputMIMEType? = nil,
        vertexCompressionQuality: Int? = nil
    ) {
        self.responseMode = responseMode
        self.aspectRatio = aspectRatio
        self.imageSize = imageSize
        self.seed = seed
        self.vertexPersonGeneration = vertexPersonGeneration
        self.vertexOutputMIMEType = vertexOutputMIMEType
        self.vertexCompressionQuality = vertexCompressionQuality
    }

    var isEmpty: Bool {
        responseMode == nil
            && aspectRatio == nil
            && imageSize == nil
            && seed == nil
            && vertexPersonGeneration == nil
            && vertexOutputMIMEType == nil
            && vertexCompressionQuality == nil
    }
}

enum ImageResponseMode: String, Codable, CaseIterable {
    case textAndImage
    case imageOnly

    var displayName: String {
        switch self {
        case .textAndImage: return "Text + Image"
        case .imageOnly: return "Image only"
        }
    }

    var responseModalities: [String] {
        switch self {
        case .textAndImage: return ["TEXT", "IMAGE"]
        case .imageOnly: return ["IMAGE"]
        }
    }
}

enum ImageAspectRatio: String, Codable, CaseIterable {
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

enum ImageOutputSize: String, Codable, CaseIterable {
    case size1K = "1K"
    case size2K = "2K"
    case size4K = "4K"

    var displayName: String { rawValue }
}

enum VertexImagePersonGeneration: String, Codable, CaseIterable {
    case unspecified = "PERSON_GENERATION_UNSPECIFIED"
    case allowNone = "ALLOW_NONE"
    case allowAdult = "ALLOW_ADULT"
    case allowAll = "ALLOW_ALL"

    var displayName: String {
        switch self {
        case .unspecified: return "Default"
        case .allowNone: return "Don't allow people"
        case .allowAdult: return "Allow adults"
        case .allowAll: return "Allow all"
        }
    }
}

enum VertexImageOutputMIMEType: String, Codable, CaseIterable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case webp = "image/webp"

    var displayName: String { rawValue }
}
