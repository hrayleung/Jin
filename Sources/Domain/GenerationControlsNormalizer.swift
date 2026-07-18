import Foundation

/// Domain-level generation control clamping shared by UI and any non-UI callers.
///
/// Provider-specific body shaping remains in adapters / UI support types; this type
/// owns model-capability-aware defaults and limits that must stay consistent everywhere.
enum GenerationControlsNormalizer {
    /// Clamp requested max tokens to the model's documented max output, if known.
    static func normalizeMaxTokensForModel(
        controls: inout GenerationControls,
        modelMaxOutputTokens: Int?
    ) {
        if let modelMaxOutputTokens,
           let requested = controls.maxTokens,
           requested > modelMaxOutputTokens {
            controls.maxTokens = modelMaxOutputTokens
        }
    }

    /// When the active model is media-generation-only, strip chat-only controls.
    static func normalizeMediaGenerationOverrides(
        controls: inout GenerationControls,
        supportsMediaGenerationControl: Bool,
        supportsReasoningControl: Bool,
        supportsWebSearchControl: Bool
    ) {
        guard supportsMediaGenerationControl else { return }
        if !supportsReasoningControl {
            controls.reasoning = nil
        }
        if !supportsWebSearchControl {
            controls.webSearch = nil
        }
        controls.searchPlugin = nil
        controls.mcpTools = nil
    }

    /// Apply the common capability-aware clamps used before send / persist.
    static func normalizeForModelCapabilities(
        controls: inout GenerationControls,
        modelMaxOutputTokens: Int?,
        supportsMediaGenerationControl: Bool,
        supportsReasoningControl: Bool,
        supportsWebSearchControl: Bool
    ) {
        normalizeMaxTokensForModel(
            controls: &controls,
            modelMaxOutputTokens: modelMaxOutputTokens
        )
        normalizeMediaGenerationOverrides(
            controls: &controls,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsReasoningControl: supportsReasoningControl,
            supportsWebSearchControl: supportsWebSearchControl
        )
    }
}
