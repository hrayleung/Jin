import Foundation

enum ChatControlNormalizationSupport {
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
}
