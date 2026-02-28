import Foundation

/// Shared model-family identification constants used by both `GeminiAdapter`
/// and `VertexAIAdapter`. Centralizes the sets so they stay in sync when new
/// models are added.
enum GeminiModelConstants {

    /// All known Gemini model IDs (lowercased) used for capability inference.
    static let knownModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-image",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    /// Gemini 3 family models (lowercased).
    static let gemini3ModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
    ]

    /// Gemini models that support native image generation (lowercased).
    static let imageGenerationModelIDs: Set<String> = [
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-2.5-flash-image",
    ]

    /// Gemini 2.5 text-only models (lowercased). Used to suppress certain
    /// VertexAI generation config fields (e.g., `thinkingLevel`).
    static let gemini25TextModelIDs: Set<String> = [
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ]

    /// Models that accept native PDF via `inlineData` (lowercased).
    /// Gemini 3 family models, plus Gemini 2.5 text models for Vertex.
    static let nativePDFModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-image-preview",
    ]

    /// Extended native PDF set for Vertex AI, which also supports Gemini 2.5 family.
    static let vertexNativePDFModelIDs: Set<String> = {
        nativePDFModelIDs.union(gemini25TextModelIDs)
    }()

    // MARK: - Query Helpers

    static func isKnownModel(_ modelID: String) -> Bool {
        knownModelIDs.contains(modelID.lowercased())
    }

    static func isGemini3Model(_ modelID: String) -> Bool {
        gemini3ModelIDs.contains(modelID.lowercased())
    }

    static func isImageGenerationModel(_ modelID: String) -> Bool {
        imageGenerationModelIDs.contains(modelID.lowercased())
    }

    static func isGemini25TextModel(_ modelID: String) -> Bool {
        gemini25TextModelIDs.contains(modelID.lowercased())
    }

    static func supportsNativePDF(_ modelID: String) -> Bool {
        nativePDFModelIDs.contains(modelID.lowercased())
    }

    static func supportsVertexNativePDF(_ modelID: String) -> Bool {
        vertexNativePDFModelIDs.contains(modelID.lowercased())
    }
}
