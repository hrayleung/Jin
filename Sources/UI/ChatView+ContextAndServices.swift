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
        ChatAuxiliaryControlSupport.supportsExplicitContextCacheMode(providerType: providerType)
    }

    var supportsContextCacheStrategy: Bool {
        ChatAuxiliaryControlSupport.supportsContextCacheStrategy(providerType: providerType)
    }

    var supportsContextCacheTTL: Bool {
        ChatAuxiliaryControlSupport.supportsContextCacheTTL(providerType: providerType)
    }

    var contextCacheSupportsAdvancedOptions: Bool {
        ChatAuxiliaryControlSupport.contextCacheSupportsAdvancedOptions(
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
    }

    var contextCacheSummaryText: String {
        ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: providerType)
    }

    var contextCacheGuidanceText: String {
        ChatAuxiliaryControlSupport.contextCacheGuidanceText(providerType: providerType)
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

    // MARK: - Codex & Service Tier

    var supportsCodexSessionControl: Bool {
        ChatAuxiliaryControlSupport.supportsCodexSessionControl(providerType: providerType)
    }

    var supportsClaudeManagedAgentSessionControl: Bool {
        ChatAuxiliaryControlSupport.supportsClaudeManagedAgentSessionControl(providerType: providerType)
    }

    var supportsOpenAIServiceTierControl: Bool {
        ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
            providerType: providerType,
            supportsMediaGenerationControl: supportsMediaGenerationControl
        )
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
        ChatAuxiliaryControlSupport.codexSessionBadgeText(controls: controls)
    }

    var claudeManagedAgentSessionOverrideCount: Int {
        controls.claudeManagedSessionOverrideCount
    }

    var claudeManagedAgentSessionBadgeText: String? {
        ChatAuxiliaryControlSupport.claudeManagedAgentSessionBadgeText(controls: controls)
    }
}
