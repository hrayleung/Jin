import Foundation

/// Shared utilities for Google Veo video generation (Gemini + Vertex AI).
enum GoogleVideoGenerationCore {

    // MARK: - Model Detection & Version

    static func isVideoGenerationModel(_ modelID: String) -> Bool {
        modelID.lowercased().contains("veo-")
    }

    /// Gemini Omni Flash exact IDs (Gemini API / Interactions). Do not prefix-match.
    static func isOmniFlashModel(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case "gemini-omni-1.1-flash", "gemini-omni-flash-preview":
            return true
        default:
            return false
        }
    }

    static func isGeminiAPIVideoGenerationModel(_ modelID: String) -> Bool {
        isVideoGenerationModel(modelID) || isOmniFlashModel(modelID)
    }

    /// Returns the Veo major version: 2, 3, or nil if unknown.
    static func veoMajorVersion(_ modelID: String) -> Int? {
        let lower = modelID.lowercased()
        if lower.contains("veo-2") { return 2 }
        if lower.contains("veo-3") { return 3 }
        return nil
    }

    /// Veo 3+ models support: resolution, seed, generateAudio (Vertex only).
    static func isVeo3OrLater(_ modelID: String) -> Bool {
        guard let version = veoMajorVersion(modelID) else { return false }
        return version >= 3
    }

    static func supportedResolutions(for modelID: String) -> [GoogleVideoResolution] {
        if isOmniFlashModel(modelID) {
            // Model card: 360p / 720p (default) / 1080p / 4K. 1080p and 4K are upscaled.
            return [.res360p, .res720p, .res1080p, .res4k]
        }
        if supports4KResolution(modelID) {
            return [.res720p, .res1080p, .res4k]
        }
        if isVeo3OrLater(modelID) {
            return [.res720p, .res1080p]
        }
        return []
    }

    /// Omni documents 16:9 (default) and 9:16 only. Veo keeps the existing menu.
    static func supportedAspectRatios(for modelID: String) -> [GoogleVideoAspectRatio] {
        if isOmniFlashModel(modelID) {
            return [.ratio16x9, .ratio9x16]
        }
        return GoogleVideoAspectRatio.allCases
    }

    static func supportsDurationControl(_ modelID: String) -> Bool {
        !isOmniFlashModel(modelID)
    }

    static func supportsPersonGenerationControl(_ modelID: String) -> Bool {
        !isOmniFlashModel(modelID)
    }

    /// Docs: use `delivery=uri` for videos larger than 4MB (>720p when available).
    static func omniUsesURIDelivery(resolution: GoogleVideoResolution?) -> Bool {
        switch resolution {
        case .res1080p, .res4k:
            return true
        default:
            return false
        }
    }

    static func sanitizedGoogleVideoControls(
        _ controls: GoogleVideoGenerationControls?,
        modelID: String
    ) -> GoogleVideoGenerationControls? {
        guard var draft = controls, !draft.isEmpty else { return nil }

        let allowedResolutions = supportedResolutions(for: modelID)
        if let resolution = draft.resolution, !allowedResolutions.contains(resolution) {
            draft.resolution = nil
        }

        let allowedAspects = supportedAspectRatios(for: modelID)
        if let aspect = draft.aspectRatio, !allowedAspects.contains(aspect) {
            draft.aspectRatio = nil
        }

        if isOmniFlashModel(modelID) {
            // Undocumented on the Interactions API; sending them 400s.
            draft.durationSeconds = nil
            draft.negativePrompt = nil
            draft.generateAudio = nil
            draft.personGeneration = nil
            draft.seed = nil
        }

        return draft.isEmpty ? nil : draft
    }

    static func supports4KResolution(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case "veo-3.1-generate-preview",
             "veo-3.1-fast-generate-preview":
            return true
        default:
            return false
        }
    }

    // MARK: - Parameter Building (Gemini API / AI Studio)

    /// Builds the `parameters` dict for the Gemini API.
    /// Gemini API does NOT support `generateAudio` (Veo 3+ generates audio by default).
    static func buildGeminiParameters(
        controls: GoogleVideoGenerationControls?,
        modelID: String
    ) -> [String: Any] {
        let isVeo3 = isVeo3OrLater(modelID)
        var parameters: [String: Any] = [:]

        if let duration = controls?.durationSeconds {
            parameters["durationSeconds"] = duration
        }
        if let aspectRatio = controls?.aspectRatio {
            parameters["aspectRatio"] = aspectRatio.rawValue
        }
        if isVeo3, let resolution = controls?.resolution {
            parameters["resolution"] = resolution.rawValue
        }
        if let negativePrompt = controls?.negativePrompt?.trimmedNonEmpty {
            parameters["negativePrompt"] = negativePrompt
        }
        if let personGeneration = controls?.personGeneration {
            parameters["personGeneration"] = personGeneration.rawValue
        }
        if isVeo3, let seed = controls?.seed {
            parameters["seed"] = seed
        }

        // Note: generateAudio is NOT a valid Gemini API parameter.
        // Veo 3+ models generate audio natively by default.

        return parameters
    }

    // MARK: - Parameter Building (Vertex AI)

    /// Builds the `parameters` dict for the Vertex AI API.
    /// Vertex supports `generateAudio` and `sampleCount` (Gemini does not).
    /// Vertex sends `durationSeconds` as an integer.
    static func buildVertexParameters(
        controls: GoogleVideoGenerationControls?,
        modelID: String
    ) -> [String: Any] {
        let isVeo3 = isVeo3OrLater(modelID)
        var parameters: [String: Any] = ["sampleCount": 1]

        if let duration = controls?.durationSeconds {
            parameters["durationSeconds"] = duration
        }
        if let aspectRatio = controls?.aspectRatio {
            parameters["aspectRatio"] = aspectRatio.rawValue
        }
        if isVeo3, let resolution = controls?.resolution {
            parameters["resolution"] = resolution.rawValue
        }
        if let negativePrompt = controls?.negativePrompt?.trimmedNonEmpty {
            parameters["negativePrompt"] = negativePrompt
        }
        if isVeo3, let generateAudio = controls?.generateAudio {
            parameters["generateAudio"] = generateAudio
        }
        if let personGeneration = controls?.personGeneration {
            parameters["personGeneration"] = personGeneration.rawValue
        }
        if let seed = controls?.seed {
            parameters["seed"] = seed
        }

        return parameters
    }

    // MARK: - Prompt Extraction

    /// Extracts the latest user text message as the video generation prompt.
    static func extractPrompt(from messages: [Message]) -> String? {
        for message in messages.reversed() where message.role == .user {
            for part in message.content {
                if case .text(let text) = part {
                    if let trimmed = text.trimmedNonEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    /// Extracts the latest user image for image-to-video generation.
    static func extractImageInput(from messages: [Message]) -> ImageContent? {
        extractImageInputs(from: messages).first
    }

    /// All images on the latest user message (Omni interpolation / subject refs).
    static func extractImageInputs(from messages: [Message]) -> [ImageContent] {
        for message in messages.reversed() where message.role == .user {
            return message.content.compactMap { part in
                if case .image(let image) = part { return image }
                return nil
            }
        }
        return []
    }

    /// Videos on the latest user message (Omni edit / extend).
    static func extractVideoInputs(from messages: [Message]) -> [VideoContent] {
        for message in messages.reversed() where message.role == .user {
            return message.content.compactMap { part in
                if case .video(let video) = part { return video }
                return nil
            }
        }
        return []
    }

    static func videoToBase64(_ video: VideoContent) throws -> String? {
        if let data = video.data {
            return data.base64EncodedString()
        }
        if let url = video.url, url.isFileURL {
            let data = try resolveFileData(from: url)
            return data.base64EncodedString()
        }
        return nil
    }

    /// Encodes an ImageContent to base64 string.
    static func imageToBase64(_ image: ImageContent) throws -> String? {
        if let data = image.data {
            return data.base64EncodedString()
        }
        if let url = image.url, url.isFileURL {
            let data = try resolveFileData(from: url)
            return data.base64EncodedString()
        }
        return nil
    }

}
