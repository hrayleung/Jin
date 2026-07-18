import Foundation

// MARK: - Gemini / Vertex declared features (catalog-layer SSoT)

extension ModelCatalog {
    /// Exact-ID feature declarations for Google AI Studio (Gemini API).
    ///
    /// Keys are bare model IDs (`gemini-3.5-flash`). Prefixed forms
    /// (`models/…`, `google/…`) are normalized via `canonicalGoogleModelID`.
    static let geminiDeclaredFeaturesByID: [String: ModelFeatures] = [
        // Gemini API Maps grounding docs (2026-07) list 2.5+ / 3.x — not Gemini 2.0 Flash.
        "gemini-2.0-flash": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-2.0-flash-001": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-2.5-flash": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-flash-lite": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-pro": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3-flash": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3-flash-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3-pro": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3-pro-image": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3-pro-image-preview": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3-pro-preview": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-3.1-flash-image": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3.1-flash-image-preview": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3.1-flash-lite": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3.1-flash-lite-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3.1-pro": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3.1-pro-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3.5-flash": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemma-4-26b-a4b-it": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemma-4-31b-it": .init(webSearch: true, googleMaps: false, codeExecution: false),
    ]

    /// Exact-ID feature declarations for Vertex AI.
    ///
    /// Maps / Search / code-execution allowlists differ from AI Studio — keep separate.
    static let vertexDeclaredFeaturesByID: [String: ModelFeatures] = [
        "gemini-2.0-flash": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.0-flash-001": .init(webSearch: false, googleMaps: true, codeExecution: true),
        "gemini-2.0-flash-live-preview-04-09": .init(webSearch: false, googleMaps: true, codeExecution: false),
        "gemini-2.5-flash": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-flash-lite": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-flash-lite-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-flash-lite-preview-09-2025": .init(webSearch: false, googleMaps: true, codeExecution: false),
        "gemini-2.5-flash-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-2.5-flash-preview-09-2025": .init(webSearch: false, googleMaps: true, codeExecution: false),
        "gemini-2.5-pro": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3-flash": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3-flash-preview": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-3-pro": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3-pro-image": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3-pro-image-preview": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3-pro-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3.1-flash-image": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3.1-flash-image-preview": .init(webSearch: true, googleMaps: false, codeExecution: false),
        "gemini-3.1-flash-lite": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-3.1-flash-lite-preview": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-3.1-pro": .init(webSearch: false, googleMaps: false, codeExecution: true),
        "gemini-3.1-pro-preview": .init(webSearch: true, googleMaps: true, codeExecution: true),
        "gemini-3.5-flash": .init(webSearch: true, googleMaps: false, codeExecution: true),
        "gemini-live-2.5-flash-native-audio": .init(webSearch: false, googleMaps: true, codeExecution: false),
        "gemini-live-2.5-flash-preview-native-audio-09-2025": .init(
            webSearch: false,
            googleMaps: true,
            codeExecution: false
        ),
    ]

    /// Strip common Google gateway / resource prefixes to a bare model ID.
    static func canonicalGoogleModelID(_ modelID: String) -> String {
        let lower = modelID.lowercased()
        let prefixes = [
            "google/",
            "google-ai-studio/",
            "google-vertex-ai/google/",
            "models/",
        ]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(lower.dropFirst(prefix.count))
        }
        return lower
    }
}
