import Foundation

enum ChatControlNormalizationSupport {
    static func normalizeMaxTokensForModel(
        controls: inout GenerationControls,
        modelMaxOutputTokens: Int?
    ) {
        GenerationControlsNormalizer.normalizeMaxTokensForModel(
            controls: &controls,
            modelMaxOutputTokens: modelMaxOutputTokens
        )
    }

    static func normalizeMediaGenerationOverrides(
        controls: inout GenerationControls,
        supportsMediaGenerationControl: Bool,
        supportsReasoningControl: Bool,
        supportsWebSearchControl: Bool
    ) {
        GenerationControlsNormalizer.normalizeMediaGenerationOverrides(
            controls: &controls,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsReasoningControl: supportsReasoningControl,
            supportsWebSearchControl: supportsWebSearchControl
        )
    }
}
