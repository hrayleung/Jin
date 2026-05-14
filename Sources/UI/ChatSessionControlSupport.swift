import Foundation

extension ChatAuxiliaryControlSupport {
    static func supportsCodexSessionControl(providerType: ProviderType?) -> Bool {
        providerType == .codexAppServer
    }

    static func supportsClaudeManagedAgentSessionControl(providerType: ProviderType?) -> Bool {
        providerType == .claudeManagedAgents
    }

    static func supportsOpenAIServiceTierControl(
        providerType: ProviderType?,
        supportsMediaGenerationControl: Bool
    ) -> Bool {
        guard !supportsMediaGenerationControl else { return false }
        return providerType == .openai || providerType == .openaiWebSocket
    }

    static func supportsAnthropicFastModeControl(
        providerType: ProviderType?,
        modelID: String?
    ) -> Bool {
        guard providerType == .anthropic, let modelID else { return false }
        return AnthropicModelLimits.supportsFastMode(for: modelID)
    }

    static func setOpenAIServiceTier(
        _ serviceTier: OpenAIServiceTier?,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.openAIServiceTier = serviceTier
        return controls
    }

    static func setAnthropicSpeed(
        _ speed: AnthropicSpeed?,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.anthropicSpeed = speed
        return controls
    }

    static func setCodeExecutionEnabled(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        var updated = controls.codeExecution ?? CodeExecutionControls()
        updated.enabled = isEnabled
        controls.codeExecution = updated
        return controls
    }
}
