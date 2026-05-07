import Foundation

extension ChatReasoningSupport {
    static func fireworksReasoningHistory(controls: GenerationControls) -> String? {
        controls.providerSpecific["reasoning_history"]?.value as? String
    }

    static func setFireworksReasoningHistory(
        _ value: String?,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        if let value {
            controls.providerSpecific["reasoning_history"] = AnyCodable(value)
        } else {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
        return controls
    }

    static func cerebrasPreservesThinking(controls: GenerationControls) -> Bool {
        // Cerebras `clear_thinking` defaults to true. Preserve thinking == clear_thinking false.
        let clear = (controls.providerSpecific["clear_thinking"]?.value as? Bool) ?? true
        return clear == false
    }

    static func setCerebrasPreservesThinking(
        _ preserve: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        if preserve {
            controls.providerSpecific["clear_thinking"] = AnyCodable(false)
        } else {
            // Use provider default (clear_thinking true).
            controls.providerSpecific.removeValue(forKey: "clear_thinking")
        }
        return controls
    }
}
