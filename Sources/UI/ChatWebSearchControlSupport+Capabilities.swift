import Foundation

extension ChatAuxiliaryControlSupport {
    static func isWebSearchEnabled(
        supportsWebSearchControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls
    ) -> Bool {
        guard supportsWebSearchControl else { return false }

        switch providerType {
        case .perplexity:
            return controls.webSearch?.enabled ?? true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .claudeManagedAgents, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .gemini, .vertexai, .morphllm, .opencodeGo, .zyphra, .none:
            return controls.webSearch?.enabled == true
        }
    }

    static func supportsNativeWebSearchControl(
        hidesManagedAgentInternalUI: Bool,
        providerType: ProviderType?,
        supportsMediaGenerationControl: Bool,
        supportsImageGenerationControl: Bool,
        supportsImageGenerationWebSearch: Bool,
        modelSupportsWebSearch: Bool
    ) -> Bool {
        guard !hidesManagedAgentInternalUI else { return false }
        guard providerType != .codexAppServer else { return false }

        if supportsMediaGenerationControl {
            if supportsImageGenerationControl {
                return supportsImageGenerationWebSearch
            }
            return false
        }

        return modelSupportsWebSearch
    }

    static func modelSupportsBuiltinSearchPluginControl(
        hidesManagedAgentInternalUI: Bool,
        providerType: ProviderType?,
        supportsMediaGenerationControl: Bool,
        modelSupportsToolCalling: Bool
    ) -> Bool {
        guard !hidesManagedAgentInternalUI else { return false }
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        return modelSupportsToolCalling
    }

    static func supportsBuiltinSearchPluginControl(
        modelSupportsBuiltinSearchPluginControl: Bool,
        webSearchPluginEnabled: Bool,
        webSearchPluginConfigured: Bool
    ) -> Bool {
        modelSupportsBuiltinSearchPluginControl && webSearchPluginEnabled && webSearchPluginConfigured
    }

    static func supportsSearchEngineModeSwitch(
        supportsNativeWebSearchControl: Bool,
        supportsBuiltinSearchPluginControl: Bool
    ) -> Bool {
        supportsNativeWebSearchControl && supportsBuiltinSearchPluginControl
    }

    static func usesBuiltinSearchPlugin(
        supportsNativeWebSearchControl: Bool,
        supportsBuiltinSearchPluginControl: Bool,
        prefersJinSearchEngine: Bool
    ) -> Bool {
        guard supportsBuiltinSearchPluginControl else { return false }
        if supportsNativeWebSearchControl {
            return prefersJinSearchEngine
        }
        return true
    }

    static func modelSupportsWebSearchControl(
        supportsNativeWebSearchControl: Bool,
        modelSupportsBuiltinSearchPluginControl: Bool
    ) -> Bool {
        supportsNativeWebSearchControl || modelSupportsBuiltinSearchPluginControl
    }

    static func supportsWebSearchControl(
        supportsNativeWebSearchControl: Bool,
        supportsBuiltinSearchPluginControl: Bool
    ) -> Bool {
        supportsNativeWebSearchControl || supportsBuiltinSearchPluginControl
    }
}
