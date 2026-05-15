import Foundation

extension ChatAuxiliaryControlSupport {
    static func effectiveContextCacheMode(
        controls: GenerationControls,
        providerType: ProviderType?
    ) -> ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic || providerType == .claudeManagedAgents {
            return .implicit
        }
        return .off
    }

    static func supportsExplicitContextCacheMode(providerType: ProviderType?) -> Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .xai, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return false
        }
    }

    static func supportsContextCacheStrategy(providerType: ProviderType?) -> Bool {
        providerType == .anthropic || providerType == .claudeManagedAgents
    }

    static func supportsContextCacheTTL(providerType: ProviderType?) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai:
            return true
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return false
        }
    }

    static func contextCacheSupportsAdvancedOptions(
        providerType: ProviderType?,
        supportsContextCacheTTL: Bool
    ) -> Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }
}
