import Foundation

extension ChatAuxiliaryControlSupport {
    static func webSearchHelpText(
        supportsWebSearchControl: Bool,
        isWebSearchEnabled: Bool,
        label: String
    ) -> String {
        guard supportsWebSearchControl else { return "Web Search: Not supported" }
        guard isWebSearchEnabled else { return "Web Search: Off" }
        return "Web Search: \(label)"
    }

    static func webSearchLabel(
        providerType: ProviderType?,
        controls: GenerationControls,
        usesBuiltinSearchPlugin: Bool,
        searchPluginProvider: SearchPluginProvider
    ) -> String {
        if usesBuiltinSearchPlugin {
            let provider = searchPluginProvider.displayName
            if let maxResults = controls.searchPlugin?.maxResults {
                return "\(provider) \u{00B7} \(maxResults) results"
            }
            return provider
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .perplexity:
            return (controls.webSearch?.contextSize ?? .low).displayName
        case .xai:
            return webSearchSourcesLabel(controls: controls)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .anthropic, .claudeManagedAgents,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return "On"
        }
    }

    static func webSearchSourcesLabel(controls: GenerationControls) -> String {
        let sources = Set(controls.webSearch?.sources ?? [])
        if sources.isEmpty { return "On" }
        if sources == [.web] { return "Web" }
        if sources == [.x] { return "X" }
        return "Web + X"
    }

    static func webSearchBadgeText(
        supportsWebSearchControl: Bool,
        isWebSearchEnabled: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        usesBuiltinSearchPlugin: Bool,
        searchPluginProvider: SearchPluginProvider
    ) -> String? {
        guard supportsWebSearchControl, isWebSearchEnabled else { return nil }

        if usesBuiltinSearchPlugin {
            return searchPluginProvider.shortBadge
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .perplexity:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "W+X" }
            return "On"
        case .anthropic, .claudeManagedAgents, .mimoTokenPlanOpenAI:
            return "On"
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return "On"
        }
    }
}
