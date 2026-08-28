import Foundation

enum GenerationControlsResolver {
    static func resolvedForRequest(
        base: GenerationControls,
        assistantTemperature: Double?,
        assistantMaxOutputTokens: Int?,
        modelMaxOutputTokens: Int?
    ) -> GenerationControls {
        var resolved = base

        if resolved.temperature == nil, let assistantTemperature {
            resolved.temperature = assistantTemperature
        }

        if resolved.maxTokens == nil, let assistantMaxOutputTokens {
            resolved.maxTokens = assistantMaxOutputTokens
        }

        // Do not auto-fill the model's absolute maximum. Providers such as Groq
        // reserve `max_tokens` against TPM, so sending 16,384 on an 8,000 TPM
        // on_demand tier fails even for a two-word prompt. The catalog maximum
        // is a clamp for explicit values, not a default reservation.
        if let modelMaxOutputTokens,
           let requested = resolved.maxTokens,
           requested > modelMaxOutputTokens {
            resolved.maxTokens = modelMaxOutputTokens
        }

        return resolved
    }
}
