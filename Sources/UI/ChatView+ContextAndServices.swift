import SwiftUI

// MARK: - Context Cache & Service Tier Controls

extension ChatView {

    // MARK: - Context Cache

    var effectiveContextCacheMode: ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic || providerType == .claudeManagedAgents {
            return .implicit
        }
        return .off
    }

    var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    var supportsContextCacheControl: Bool {
        false
    }

    var supportsExplicitContextCacheMode: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .xai, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return false
        }
    }

    var supportsContextCacheStrategy: Bool {
        providerType == .anthropic || providerType == .claudeManagedAgents
    }

    var supportsContextCacheTTL: Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai:
            return true
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return false
        }
    }

    var contextCacheSupportsAdvancedOptions: Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }

    var contextCacheSummaryText: String {
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
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return "Context cache controls are only available for providers with native prompt caching support."
        }
    }

    var contextCacheGuidanceText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        case .openai, .openaiWebSocket, .xai:
            return "Use a stable cache key when your prompt prefix is consistent."
        case .anthropic, .claudeManagedAgents:
            return "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        }
    }

    func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?
    ) -> ContextCacheControls? {
        ChatAuxiliaryControlSupport.automaticContextCacheControls(
            providerType: providerType,
            modelID: modelID,
            modelCapabilities: modelCapabilities,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            conversationID: conversationEntity.id
        )
    }

    var contextCacheLabel: String {
        let mode = effectiveContextCacheMode
        switch mode {
        case .off:
            return "Off"
        case .implicit:
            return "Implicit"
        case .explicit:
            if let name = controls.contextCache?.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return "Explicit (\(name))"
            }
            return "Explicit"
        }
    }

    var contextCacheBadgeText: String? {
        guard supportsContextCacheControl, isContextCacheEnabled else { return nil }
        switch effectiveContextCacheMode {
        case .off:
            return nil
        case .implicit:
            return "I"
        case .explicit:
            return "E"
        }
    }

    var contextCacheHelpText: String {
        guard supportsContextCacheControl else { return "Context Cache: Not supported" }
        guard isContextCacheEnabled else { return "Context Cache: Off" }
        return "Context Cache: \(contextCacheLabel)"
    }

    // MARK: - Codex & Service Tier

    var supportsCodexSessionControl: Bool {
        providerType == .codexAppServer
    }

    var supportsClaudeManagedAgentSessionControl: Bool {
        providerType == .claudeManagedAgents
    }

    var supportsOpenAIServiceTierControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        return providerType == .openai || providerType == .openaiWebSocket
    }

    var isAgentModeConfigured: Bool {
        AppPreferences.isPluginEnabled("agent_mode")
    }

    var codexWorkingDirectory: String? {
        controls.codexWorkingDirectory
    }

    var codexSessionOverrideCount: Int {
        controls.codexActiveOverrideCount
    }

    var codexSessionBadgeText: String? {
        guard codexSessionOverrideCount > 0 else { return nil }
        return controls.codexSandboxMode.badgeText
    }

    var claudeManagedAgentSessionOverrideCount: Int {
        controls.claudeManagedSessionOverrideCount
    }

    var claudeManagedAgentSessionBadgeText: String? {
        guard claudeManagedAgentSessionOverrideCount > 0 else { return nil }
        if controls.claudeManagedAgentID != nil, controls.claudeManagedEnvironmentID != nil {
            return "2"
        }
        return "1"
    }
}
