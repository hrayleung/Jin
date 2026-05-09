import SwiftUI

// MARK: - Auxiliary Control Actions

extension ChatView {

    var supportsAnthropicDynamicFiltering: Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerType,
            modelID: activeModelID
        )
    }

    func openAnthropicWebSearchEditor() {
        let prepared = ChatAuxiliaryControlSupport.prepareAnthropicWebSearchEditorDraft(
            webSearch: controls.webSearch,
            currentMode: anthropicWebSearchDomainMode
        )
        anthropicWebSearchAllowedDomainsDraft = prepared.allowedDomainsDraft
        anthropicWebSearchBlockedDomainsDraft = prepared.blockedDomainsDraft
        anthropicWebSearchDomainMode = prepared.domainMode
        anthropicWebSearchLocationDraft = prepared.locationDraft
        anthropicWebSearchDraftError = nil
        showingAnthropicWebSearchSheet = true
    }

    func applyAnthropicWebSearchDraft() {
        switch ChatAuxiliaryControlSupport.applyAnthropicWebSearchDraft(
            domainMode: anthropicWebSearchDomainMode,
            allowedDomainsDraft: anthropicWebSearchAllowedDomainsDraft,
            blockedDomainsDraft: anthropicWebSearchBlockedDomainsDraft,
            locationDraft: anthropicWebSearchLocationDraft,
            controls: controls
        ) {
        case .success(let updatedControls):
            controls = updatedControls
            anthropicWebSearchDraftError = nil
            persistControlsToConversation()
            showingAnthropicWebSearchSheet = false
        case .failure(let error):
            anthropicWebSearchDraftError = error.localizedDescription
        }
    }

    func shouldExpandContextCacheAdvancedOptions(for draft: ContextCacheControls) -> Bool {
        ChatAuxiliaryControlSupport.shouldExpandContextCacheAdvancedOptions(
            for: draft,
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
    }

    var isContextCacheDraftValid: Bool {
        ChatAuxiliaryControlSupport.isContextCacheDraftValid(
            contextCacheDraft: contextCacheDraft,
            ttlPreset: contextCacheTTLPreset,
            customTTLDraft: contextCacheCustomTTLDraft,
            minTokensDraft: contextCacheMinTokensDraft,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode
        )
    }

    @discardableResult
    func applyContextCacheDraft() -> Bool {
        switch ChatAuxiliaryControlSupport.applyContextCacheDraft(
            draft: contextCacheDraft,
            ttlPreset: contextCacheTTLPreset,
            customTTLDraft: contextCacheCustomTTLDraft,
            minTokensDraft: contextCacheMinTokensDraft,
            supportsContextCacheTTL: supportsContextCacheTTL,
            supportsContextCacheStrategy: supportsContextCacheStrategy,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            providerType: providerType,
            controls: controls
        ) {
        case .success(let applied):
            controls = applied.controls
            contextCacheDraft = applied.contextCache ?? ContextCacheControls(mode: .off)
            normalizeControlsForCurrentSelection()
            persistControlsToConversation()
            contextCacheDraftError = nil
            return true
        case .failure(let error):
            contextCacheDraftError = error.localizedDescription
            return false
        }
    }

    func mcpServerSelectionBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedMCPServerIDs.contains(serverID)
            },
            set: { isOn in
                controls = ChatAuxiliaryControlSupport.toggleMCPServerSelection(
                    controls: controls,
                    eligibleServers: eligibleMCPServers,
                    serverID: serverID,
                    isOn: isOn
                )
                persistControlsToConversation()
            }
        )
    }

    func resetMCPServerSelection() {
        controls = ChatAuxiliaryControlSupport.resetMCPServerSelection(controls: controls)
        persistControlsToConversation()
    }

    func resolvedMCPServerConfigs(for controlsToUse: GenerationControls) throws -> [MCPServerConfig] {
        try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controlsToUse,
            supportsMCPToolsControl: supportsMCPToolsControl,
            servers: mcpServers
        )
    }
}
