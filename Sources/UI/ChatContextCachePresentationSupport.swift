import Foundation

extension ChatAuxiliaryControlSupport {
    static func contextCacheSummaryText(providerType: ProviderType?) -> String {
        switch providerType {
        case .gemini, .vertexai:
            return "Use implicit caching for normal chats, or explicit caching with a cached content resource for long reusable context."
        case .anthropic, .claudeManagedAgents:
            return "Anthropic caches tagged prompt blocks. Keep stable system/tool prefixes to improve cache hit rates."
        case .openai, .openaiWebSocket:
            return "OpenAI uses prompt cache hints. A stable key and retention hint can improve reuse across similar prompts."
        case .xai:
            return "xAI supports prompt cache hints and optional conversation scoping for continuity across related turns."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return "Context cache controls are only available for providers with native prompt caching support."
        }
    }

    static func contextCacheGuidanceText(providerType: ProviderType?) -> String {
        switch providerType {
        case .gemini, .vertexai:
            return "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        case .openai, .openaiWebSocket, .xai:
            return "Use a stable cache key when your prompt prefix is consistent."
        case .anthropic, .claudeManagedAgents:
            return "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        }
    }

    static func contextCacheLabel(
        mode: ContextCacheMode,
        controls: ContextCacheControls?
    ) -> String {
        switch mode {
        case .off:
            return "Off"
        case .implicit:
            return "Implicit"
        case .explicit:
            if let name = controls?.cachedContentName?.trimmedNonEmpty {
                return "Explicit (\(name))"
            }
            return "Explicit"
        }
    }

    static func contextCacheBadgeText(
        supportsContextCacheControl: Bool,
        mode: ContextCacheMode
    ) -> String? {
        guard supportsContextCacheControl, mode != .off else { return nil }
        switch mode {
        case .off:
            return nil
        case .implicit:
            return "I"
        case .explicit:
            return "E"
        }
    }

    static func contextCacheHelpText(
        supportsContextCacheControl: Bool,
        mode: ContextCacheMode,
        label: String
    ) -> String {
        guard supportsContextCacheControl else { return "Context Cache: Not supported" }
        guard mode != .off else { return "Context Cache: Off" }
        return "Context Cache: \(label)"
    }
}
