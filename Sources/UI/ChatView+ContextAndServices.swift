import SwiftUI

// MARK: - Context Cache & Service Tier Controls

extension ChatView {

    // MARK: - Context Cache

    var effectiveContextCacheMode: ContextCacheMode {
        ChatAuxiliaryControlSupport.effectiveContextCacheMode(
            controls: controls,
            providerType: providerType
        )
    }

    var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    var supportsContextCacheControl: Bool {
        false
    }

    var supportsExplicitContextCacheMode: Bool {
        ChatAuxiliaryControlSupport.supportsExplicitContextCacheMode(providerType: providerType, modelID: activeModelID)
    }

    var supportsContextCacheStrategy: Bool {
        ChatAuxiliaryControlSupport.supportsContextCacheStrategy(providerType: providerType)
    }

    var supportsContextCacheTTL: Bool {
        ChatAuxiliaryControlSupport.supportsContextCacheTTL(providerType: providerType)
    }

    var usesGPT62CacheTTL: Bool {
        (providerType == .openai || providerType == .openaiWebSocket)
            && OpenAIModelSupport.isGPT62(activeModelID)
    }

    var contextCacheSupportsAdvancedOptions: Bool {
        ChatAuxiliaryControlSupport.contextCacheSupportsAdvancedOptions(
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
    }

    var contextCacheSummaryText: String {
        ChatAuxiliaryControlSupport.contextCacheSummaryText(
            providerType: providerType, supportsExplicitMode: supportsExplicitContextCacheMode
        )
    }

    var contextCacheGuidanceText: String {
        ChatAuxiliaryControlSupport.contextCacheGuidanceText(
            providerType: providerType, supportsExplicitMode: supportsExplicitContextCacheMode
        )
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
        ChatAuxiliaryControlSupport.contextCacheLabel(
            mode: effectiveContextCacheMode,
            controls: controls.contextCache
        )
    }

    var contextCacheBadgeText: String? {
        ChatAuxiliaryControlSupport.contextCacheBadgeText(
            supportsContextCacheControl: supportsContextCacheControl,
            mode: effectiveContextCacheMode
        )
    }

    var contextCacheHelpText: String {
        ChatAuxiliaryControlSupport.contextCacheHelpText(
            supportsContextCacheControl: supportsContextCacheControl,
            mode: effectiveContextCacheMode,
            label: contextCacheLabel
        )
    }

    // MARK: - Service Tier

    var supportsClaudeManagedAgentSessionControl: Bool {
        ChatAuxiliaryControlSupport.supportsClaudeManagedAgentSessionControl(providerType: providerType)
    }

    var supportsOpenAIServiceTierControl: Bool {
        if providerType == .vercelAIGateway {
            return OpenAIServiceTier.supportsUltrafast(modelID: activeModelID, providerType: providerType)
        }
        return ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
            providerType: providerType,
            supportsMediaGenerationControl: supportsMediaGenerationControl
        )
    }

    var selectedOpenAIServiceTier: OpenAIServiceTier? {
        OpenAIServiceTier.selected(in: controls, modelID: activeModelID, providerType: providerType)
    }

    var supportsAnthropicFastModeControl: Bool {
        ChatAuxiliaryControlSupport.supportsAnthropicFastModeControl(
            providerType: providerType,
            modelID: activeModelID
        )
    }

    var claudeManagedAgentSessionOverrideCount: Int {
        controls.claudeManagedSessionOverrideCount
    }

    var claudeManagedAgentSessionBadgeText: String? {
        ChatAuxiliaryControlSupport.claudeManagedAgentSessionBadgeText(controls: controls)
    }
}
