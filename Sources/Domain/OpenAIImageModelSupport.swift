import Foundation

enum OpenAIImageModelFamily: Sendable {
    case gptImage1
    case gptImage15
    case gptImage1Mini
    case gptImage2
    case gptImage25
    case gptImage26
    case dallE3
    case dallE2

    var isGPTImageModel: Bool {
        switch self {
        case .gptImage1, .gptImage15, .gptImage1Mini, .gptImage2, .gptImage25, .gptImage26:
            return true
        case .dallE3, .dallE2:
            return false
        }
    }
}

struct OpenAIImageModelProfile: Sendable {
    let family: OpenAIImageModelFamily
    let ids: Set<String>
    let supportsEdits: Bool
    let usesMultipartEdits: Bool
    let presetSizes: [OpenAIImageSize]
    let supportsCustomSize: Bool
    let qualityOptions: [OpenAIImageQuality]
    let supportsStyle: Bool
    let backgroundOptions: [OpenAIImageBackground]
    let supportsOutputFormat: Bool
    let supportsOutputCompression: Bool
    let supportsModeration: Bool
    let supportsInputFidelity: Bool

    var isGPTImageModel: Bool {
        family.isGPTImageModel
    }

    var supportsComplexity: Bool { family == .gptImage26 }
    var supportsEditGuidance: Bool { family == .gptImage26 }
    var outputFormats: [OpenAIImageOutputFormat] {
        guard supportsOutputFormat else { return [] }
        return family == .gptImage26 ? [.png, .jpeg, .webp, .svg, .gif] : OpenAIImageOutputFormat.rasterFormats
    }
}

enum OpenAIImageModelSupport {
    static let gptImage1Profile = OpenAIImageModelProfile(
        family: .gptImage1,
        ids: ["gpt-image-1"],
        supportsEdits: true,
        usesMultipartEdits: false,
        presetSizes: OpenAIImageSize.gptImageLegacyPresetSizes,
        supportsCustomSize: false,
        qualityOptions: OpenAIImageQuality.gptImageQualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: true
    )

    static let gptImage15Profile = OpenAIImageModelProfile(
        family: .gptImage15,
        ids: ["gpt-image-1.5"],
        supportsEdits: true,
        usesMultipartEdits: false,
        presetSizes: OpenAIImageSize.gptImageLegacyPresetSizes,
        supportsCustomSize: false,
        qualityOptions: OpenAIImageQuality.gptImageQualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    static let gptImage1MiniProfile = OpenAIImageModelProfile(
        family: .gptImage1Mini,
        ids: ["gpt-image-1-mini"],
        supportsEdits: true,
        usesMultipartEdits: false,
        presetSizes: OpenAIImageSize.gptImageLegacyPresetSizes,
        supportsCustomSize: false,
        qualityOptions: OpenAIImageQuality.gptImageQualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    static let gptImage2Profile = OpenAIImageModelProfile(
        family: .gptImage2,
        ids: ["gpt-image-2", "gpt-image-2-2026-04-21"],
        supportsEdits: true,
        usesMultipartEdits: true,
        presetSizes: OpenAIImageSize.gptImage2SuggestedSizes,
        supportsCustomSize: true,
        qualityOptions: OpenAIImageQuality.gptImageQualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    static let gptImage25FlareProfile = OpenAIImageModelProfile(
        family: .gptImage25,
        ids: ["gpt-image-2.5-flare", "gpt-image-2.5-flare-2026-09-08"],
        supportsEdits: true,
        usesMultipartEdits: true,
        presetSizes: OpenAIImageSize.gptImage2SuggestedSizes,
        supportsCustomSize: true,
        qualityOptions: OpenAIImageQuality.gptImage25Qualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    static let gptImage25SunburstProfile = OpenAIImageModelProfile(
        family: .gptImage25,
        ids: ["gpt-image-2.5-sunburst", "gpt-image-2.5-sunburst-2026-09-08"],
        supportsEdits: true,
        usesMultipartEdits: true,
        presetSizes: OpenAIImageSize.gptImage2SuggestedSizes,
        supportsCustomSize: true,
        qualityOptions: OpenAIImageQuality.gptImage25Qualities,
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    // Exact model pages + image guide and its GPT Image 2.6 cost calculator,
    // verified 2026-11-05: low/medium/high/xhigh/max, 16px steps, 3840px edge,
    // 655,360...8,294,400 pixels, maximum 3:1 aspect ratio. No dated aliases published.
    static let gptImage26Profile = OpenAIImageModelProfile(
        family: .gptImage26,
        ids: ["gpt-image-2.6-flare", "gpt-image-2.6-sunburst"],
        supportsEdits: true,
        usesMultipartEdits: true,
        presetSizes: OpenAIImageSize.gptImage2SuggestedSizes,
        supportsCustomSize: true,
        qualityOptions: [.auto, .low, .medium, .high, .xhigh, .max],
        supportsStyle: false,
        backgroundOptions: [.auto, .transparent, .opaque],
        supportsOutputFormat: true,
        supportsOutputCompression: true,
        supportsModeration: true,
        supportsInputFidelity: false
    )

    static let dallE3Profile = OpenAIImageModelProfile(
        family: .dallE3,
        ids: ["dall-e-3"],
        supportsEdits: false,
        usesMultipartEdits: false,
        presetSizes: OpenAIImageSize.dallE3Sizes,
        supportsCustomSize: false,
        qualityOptions: OpenAIImageQuality.dallE3Qualities,
        supportsStyle: true,
        backgroundOptions: [],
        supportsOutputFormat: false,
        supportsOutputCompression: false,
        supportsModeration: false,
        supportsInputFidelity: false
    )

    static let dallE2Profile = OpenAIImageModelProfile(
        family: .dallE2,
        ids: ["dall-e-2"],
        supportsEdits: true,
        usesMultipartEdits: false,
        presetSizes: OpenAIImageSize.dallE2Sizes,
        supportsCustomSize: false,
        qualityOptions: [],
        supportsStyle: false,
        backgroundOptions: [],
        supportsOutputFormat: false,
        supportsOutputCompression: false,
        supportsModeration: false,
        supportsInputFidelity: false
    )

    static let allProfiles: [OpenAIImageModelProfile] = [
        gptImage1Profile,
        gptImage15Profile,
        gptImage1MiniProfile,
        gptImage2Profile,
        gptImage25FlareProfile,
        gptImage25SunburstProfile,
        gptImage26Profile,
        dallE3Profile,
        dallE2Profile,
    ]

    private static let profileLookup: [String: OpenAIImageModelProfile] = {
        var lookup: [String: OpenAIImageModelProfile] = [:]
        for profile in allProfiles {
            for id in profile.ids {
                lookup[id] = profile
            }
        }
        return lookup
    }()

    static let imageGenerationModelIDs: Set<String> = Set(profileLookup.keys)

    static let imageEditSupportedModelIDs: Set<String> = {
        Set(allProfiles.filter(\.supportsEdits).flatMap(\.ids))
    }()

    static func profile(for modelID: String) -> OpenAIImageModelProfile? {
        profileLookup[modelID.trimmedLowercased]
    }

    static func isImageGenerationModel(_ modelID: String) -> Bool {
        profile(for: modelID) != nil
    }

    static func supportsEdits(_ modelID: String) -> Bool {
        profile(for: modelID)?.supportsEdits == true
    }

    static func supportsMultipartEdits(_ modelID: String) -> Bool {
        profile(for: modelID)?.usesMultipartEdits == true
    }

    static func validate(size: OpenAIImageSize, for modelID: String, outputFormat: OpenAIImageOutputFormat? = nil) -> String? {
        guard let profile = profile(for: modelID) else {
            return "This OpenAI image model is not in Jin's exact support table."
        }

        // GIF frame dimensions have their own documented rule. Aggregate frame
        // pixel budgets are enforced by OpenAI; no undocumented cap is guessed.
        if profile.family == .gptImage26, outputFormat == .gif {
            if size.isAuto { return nil }
            guard let (width, height) = size.pixelDimensions,
                  width > 0, height > 0, width % 16 == 0, height % 16 == 0,
                  !width.multipliedReportingOverflow(by: height).overflow else {
                return "GIF frame dimensions must be positive multiples of 16."
            }
            return nil
        }

        if profile.presetSizes.contains(size) {
            return nil
        }

        guard profile.supportsCustomSize else {
            return "Unsupported size for \(displayName(for: modelID))."
        }

        guard let (width, height) = size.pixelDimensions else {
            return "Custom size must be `WIDTHxHEIGHT` or `auto`."
        }

        if width <= 0 || height <= 0 {
            return "Width and height must be positive integers."
        }

        if width % 16 != 0 || height % 16 != 0 {
            return "Width and height must both be multiples of 16."
        }

        if max(width, height) > 3_840 {
            return "The largest side cannot exceed 3840 pixels."
        }

        if Double(max(width, height)) / Double(min(width, height)) > 3 {
            return "Aspect ratio cannot exceed 3:1."
        }

        let totalPixels = width * height
        if totalPixels < 655_360 || totalPixels > 8_294_400 {
            return "Total pixels must be between 655,360 and 8,294,400."
        }

        return nil
    }

    static func sizeConstraintSummary(for modelID: String, outputFormat: OpenAIImageOutputFormat? = nil) -> String {
        guard let profile = profile(for: modelID) else { return "" }
        if profile.family == .gptImage26, outputFormat == .gif {
            return "Frame dimensions must be positive multiples of 16. OpenAI also limits the total pixels across frames and animations; use Auto or reduce dimensions and frame count if the request exceeds that budget."
        }
        let presetSummary = profile.presetSizes.map(\.displayName).joined(separator: ", ")

        if profile.supportsCustomSize {
            return "Suggested presets: \(presetSummary). Custom sizes must use `WIDTHxHEIGHT`, stay within 16-pixel steps, max side 3840, aspect ratio up to 3:1, and total pixels between 655,360 and 8,294,400."
        }

        return "Supported sizes: \(presetSummary)."
    }

    static func displayName(for modelID: String) -> String {
        switch profile(for: modelID)?.family {
        case .gptImage1: return "GPT Image 1"
        case .gptImage15: return "GPT Image 1.5"
        case .gptImage1Mini: return "GPT Image 1 Mini"
        case .gptImage2: return "GPT Image 2"
        case .gptImage25: return "GPT Image 2.5"
        case .gptImage26: return "GPT Image 2.6"
        case .dallE3: return "DALL-E 3"
        case .dallE2: return "DALL-E 2"
        case nil: return modelID
        }
    }
}
