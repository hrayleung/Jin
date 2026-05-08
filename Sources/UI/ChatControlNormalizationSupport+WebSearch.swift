import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeAnthropicDomainFilters(controls: inout GenerationControls) {
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.blockedDomains)

        if !allowed.isEmpty {
            controls.webSearch?.allowedDomains = allowed
            controls.webSearch?.blockedDomains = nil
        } else if !blocked.isEmpty {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = blocked
        } else {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        }
    }

    static func defaultWebSearchControls(enabled: Bool, providerType: ProviderType?) -> WebSearchControls {
        guard enabled else { return WebSearchControls(enabled: false) }

        switch providerType {
        case .openai, .openaiWebSocket:
            return WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        case .perplexity:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .mimoTokenPlanOpenAI:
            return WebSearchControls(enabled: true, maxUses: 3)
        case .anthropic, .claudeManagedAgents:
            return WebSearchControls(enabled: true)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        }
    }

    static func ensureValidWebSearchDefaultsIfEnabled(
        controls: inout GenerationControls,
        providerType: ProviderType?
    ) {
        guard controls.webSearch?.enabled == true else { return }
        switch providerType {
        case .openai, .openaiWebSocket:
            controls.webSearch?.sources = nil
            if controls.webSearch?.contextSize == nil {
                controls.webSearch?.contextSize = .medium
            }
        case .perplexity:
            controls.webSearch?.sources = nil
        case .xai:
            controls.webSearch?.contextSize = nil
            let sources = controls.webSearch?.sources ?? []
            if sources.isEmpty {
                controls.webSearch?.sources = [.web]
            }
        case .mimoTokenPlanOpenAI:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
            controls.webSearch?.dynamicFiltering = nil
            if let maxUses = controls.webSearch?.maxUses, maxUses <= 0 {
                controls.webSearch?.maxUses = nil
            }
        case .anthropic, .claudeManagedAgents:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
            normalizeAnthropicDomainFilters(controls: &controls)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    static func normalizeWebSearchControls(
        controls: inout GenerationControls,
        modelSupportsWebSearchControl: Bool,
        providerType: ProviderType?
    ) {
        guard modelSupportsWebSearchControl else {
            controls.webSearch = nil
            return
        }

        ensureValidWebSearchDefaultsIfEnabled(
            controls: &controls,
            providerType: providerType
        )
    }

    static func normalizeSearchPluginControls(
        controls: inout GenerationControls,
        modelSupportsBuiltinSearchPluginControl: Bool
    ) {
        if !modelSupportsBuiltinSearchPluginControl {
            controls.searchPlugin = nil
            return
        }

        guard controls.webSearch?.enabled == true else {
            return
        }

        guard var plugin = controls.searchPlugin else {
            return
        }

        if let maxResults = plugin.maxResults {
            plugin.maxResults = max(1, min(50, maxResults))
        }
        if let recencyDays = plugin.recencyDays {
            plugin.recencyDays = max(1, min(365, recencyDays))
        }

        controls.searchPlugin = plugin
    }
}
