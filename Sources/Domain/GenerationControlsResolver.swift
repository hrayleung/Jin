import Foundation

enum GenerationControlsResolver {
    static func resolvedForRequest(
        base: GenerationControls,
        assistantTemperature: Double?,
        assistantMaxOutputTokens: Int?
    ) -> GenerationControls {
        var resolved = base

        if resolved.temperature == nil, let assistantTemperature {
            resolved.temperature = assistantTemperature
        }

        if resolved.maxTokens == nil, let assistantMaxOutputTokens {
            resolved.maxTokens = assistantMaxOutputTokens
        }

        return resolved
    }
}
