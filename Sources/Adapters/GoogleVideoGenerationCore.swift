import Foundation

/// Shared utilities for Google Veo video generation (Gemini + Vertex AI).
enum GoogleVideoGenerationCore {

    // MARK: - Model Detection & Version

    static func isVideoGenerationModel(_ modelID: String) -> Bool {
        modelID.lowercased().contains("veo-")
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
        if let negativePrompt = controls?.negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !negativePrompt.isEmpty {
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
        if let negativePrompt = controls?.negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !negativePrompt.isEmpty {
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
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    /// Extracts the latest user image for image-to-video generation.
    static func extractImageInput(from messages: [Message]) -> ImageContent? {
        for message in messages.reversed() where message.role == .user {
            for part in message.content {
                if case .image(let image) = part {
                    return image
                }
            }
        }
        return nil
    }

    /// Encodes an ImageContent to base64 string.
    static func imageToBase64(_ image: ImageContent) -> String? {
        if let data = image.data {
            return data.base64EncodedString()
        }
        if let url = image.url, url.isFileURL,
           let data = try? Data(contentsOf: url) {
            return data.base64EncodedString()
        }
        return nil
    }

    // MARK: - Video Download & Save

    /// Downloads a video from a URL and saves it to the local attachments directory.
    static func downloadVideoToLocal(
        from url: URL,
        networkManager: NetworkManager,
        authHeader: (key: String, value: String)? = nil
    ) async throws -> (localURL: URL, mimeType: String) {
        try await VideoAttachmentUtility.downloadToLocal(
            from: url,
            networkManager: networkManager,
            authHeader: authHeader
        )
    }

    /// Saves base64-decoded video data to the local attachments directory.
    static func saveVideoDataToLocal(_ data: Data, mimeType: String) throws -> URL {
        try VideoAttachmentUtility.saveDataToLocal(data, mimeType: mimeType)
    }

    // MARK: - Format Resolution

    static func resolveVideoFormat(contentType: String?, url: URL) -> (mimeType: String, ext: String) {
        VideoAttachmentUtility.resolveVideoFormat(contentType: contentType, url: url)
    }
}
