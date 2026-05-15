import Foundation

extension ChatReasoningSupport {
    static func reasoningHelpText(
        supportsReasoningControl: Bool,
        providerType: ProviderType?,
        label: String
    ) -> String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .claudeManagedAgents, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .gemini, .vertexai:
            return "Thinking: \(label)"
        case .perplexity:
            return "Reasoning: \(label)"
        case .openai, .openaiWebSocket, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo,
             .zyphra, .none:
            return "Reasoning: \(label)"
        }
    }

    static func reasoningBadgeText(
        supportsReasoningControl: Bool,
        isReasoningEnabled: Bool,
        selectedReasoningConfig: ModelReasoningConfig?,
        controls: GenerationControls
    ) -> String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            case .max: return "Max"
            }
        case .toggle:
            return "On"
        case .none:
            return nil
        }
    }
}
