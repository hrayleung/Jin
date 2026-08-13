import SwiftData
import SwiftUI

// MARK: - Control Persistence & Normalization

extension ChatView {

    func loadControlsFromConversation() {
        canonicalizeConversationModelIDIfNeeded()

        controls = (try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData))
            ?? GenerationControls()
        normalizeControlsForCurrentSelection()
        syncGoogleMapsLocationBiasSnapshot()
    }

    func persistControlsToConversation() {
        // Paint the chrome first. Encode + SwiftData save used to run inside
        // the Menu/Toggle action and freeze the badge under the menu.
        syncGoogleMapsLocationBiasSnapshot()
        scheduleGenerationControlsPersist()
    }

    func applyComposerControlMutation(_ mutate: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            mutate()
        }
        persistControlsToConversation()
    }

    func scheduleGenerationControlsPersist() {
        pendingGenerationControlsPersistTask?.cancel()
        pendingGenerationControlsPersistTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            commitGenerationControlsToConversation(save: true)
            pendingGenerationControlsPersistTask = nil
        }
    }

    func flushGenerationControlsPersist(save: Bool = true) {
        pendingGenerationControlsPersistTask?.cancel()
        pendingGenerationControlsPersistTask = nil
        commitGenerationControlsToConversation(save: save)
    }

    func commitGenerationControlsToConversation(save: Bool) {
        do {
            let merged = ChatGenerationControlsPersistenceSupport.mergedForPersist(
                live: controls,
                stored: storedGenerationControls()
            )
            if let encoded = ChatGenerationControlsPersistenceSupport.encodedPayloadIfChanged(
                merged: merged,
                currentData: conversationEntity.modelConfigData
            ) {
                // Do not bump `updatedAt`. That watermark means message activity
                // (sidebar sort + timeline cache rebuild), not a settings tweak.
                conversationEntity.modelConfigData = encoded
            } else if !save {
                return
            }

            // Always save when asked. Callers such as `setProviderAndModel`
            // may have already mutated provider/model fields and rely on this
            // helper as their only `modelContext.save()`.
            if save {
                try modelContext.save()
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func syncGoogleMapsLocationBiasSnapshot() {
        let next = ChatGenerationControlsPersistenceSupport.googleMapsLocationBias(from: controls)
        guard googleMapsLocationBiasSnapshot != next else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            googleMapsLocationBiasSnapshot = next
        }
    }

    func defaultWebSearchControls(enabled: Bool) -> WebSearchControls {
        ChatControlNormalizationSupport.defaultWebSearchControls(
            enabled: enabled,
            providerType: providerType
        )
    }

    func ensureValidWebSearchDefaultsIfEnabled() {
        ChatControlNormalizationSupport.ensureValidWebSearchDefaultsIfEnabled(
            controls: &controls,
            providerType: providerType
        )
    }

    func normalizeControlsForCurrentSelection() {

        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        normalizeMaxTokensForModel()
        normalizeMediaGenerationOverrides()
        normalizeReasoningControls()
        normalizeReasoningEffortLimits()
        normalizeVertexAIGenerationConfig()
        normalizeFireworksProviderSpecific()
        normalizeAnthropicProviderSpecific()
        normalizeClaudeManagedAgentProviderSpecific()
        normalizeOpenAIServiceTierControls()
        normalizeWebSearchControls()
        normalizeGoogleMapsControls()
        normalizeSearchPluginControls()
        normalizeContextCacheControls()
        normalizeMCPToolsControls()
        normalizeAnthropicMaxTokens()
        normalizeImageGenerationControls()
        normalizeVideoGenerationControls()

        let newData = (try? JSONEncoder().encode(controls)) ?? Data()
        if newData != originalData {
            persistControlsToConversation()
        }
    }

    func normalizeMaxTokensForModel() {
        ChatControlNormalizationSupport.normalizeMaxTokensForModel(
            controls: &controls,
            modelMaxOutputTokens: resolvedModelSettings?.maxOutputTokens
        )
    }

    func normalizeMediaGenerationOverrides() {
        ChatControlNormalizationSupport.normalizeMediaGenerationOverrides(
            controls: &controls,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsReasoningControl: supportsReasoningControl,
            supportsWebSearchControl: supportsWebSearchControl
        )
    }

    func normalizeReasoningControls() {
        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: supportsReasoningControl,
            selectedReasoningConfig: selectedReasoningConfig,
            providerType: providerType,
            modelID: activeModelID,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            reasoningMustRemainEnabled: reasoningMustRemainEnabled,
            defaultAnthropicEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultAnthropicBudget: anthropicDefaultBudgetTokens
        )
    }

    func normalizeReasoningEffortLimits() {
        ChatReasoningSupport.normalizeReasoningEffortLimits(
            controls: &controls,
            supportsReasoningControl: supportsReasoningControl,
            providerType: providerType,
            modelID: activeModelID,
            defaultAnthropicEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultAnthropicBudget: anthropicDefaultBudgetTokens
        )
    }

    func normalizeVertexAIGenerationConfig() {
        ChatControlNormalizationSupport.normalizeVertexAIGenerationConfig(
            controls: &controls,
            providerType: providerType,
            lowerModelID: lowerModelID,
            vertexGemini25TextModelIDs: Self.vertexGemini25TextModelIDs
        )
    }

    func normalizeFireworksProviderSpecific() {
        ChatControlNormalizationSupport.normalizeFireworksProviderSpecific(
            controls: &controls,
            providerType: providerType,
            isMiniMaxM2FamilyModel: isFireworksMiniMaxM2FamilyModel(activeModelID),
            fireworksReasoningHistoryOptions: fireworksReasoningHistoryOptions
        )
    }

    func normalizeAnthropicProviderSpecific() {
        ChatControlNormalizationSupport.normalizeAnthropicProviderSpecific(
            controls: &controls,
            providerType: providerType,
            modelID: activeModelID
        )
    }

    func normalizeClaudeManagedAgentProviderSpecific() {
        ChatControlNormalizationSupport.normalizeClaudeManagedAgentProviderSpecific(
            controls: &controls,
            providerType: providerType
        )
    }

    func normalizeOpenAIServiceTierControls() {
        ChatControlNormalizationSupport.normalizeOpenAIServiceTierControls(
            controls: &controls
        )
    }

    nonisolated static func sanitizeProviderSpecificForProvider(_ providerType: ProviderType?, controls: inout GenerationControls) {
        ChatControlNormalizationSupport.sanitizeProviderSpecificForProvider(
            providerType,
            controls: &controls
        )
    }

    func normalizeWebSearchControls() {
        ChatControlNormalizationSupport.normalizeWebSearchControls(
            controls: &controls,
            modelSupportsWebSearchControl: modelSupportsWebSearchControl,
            providerType: providerType
        )
    }

    func normalizeGoogleMapsControls() {
        ChatControlNormalizationSupport.normalizeGoogleMapsControls(
            controls: &controls,
            providerType: providerType,
            supportsGoogleMapsControl: supportsGoogleMapsControl
        )
    }

    func normalizeSearchPluginControls() {
        ChatControlNormalizationSupport.normalizeSearchPluginControls(
            controls: &controls,
            modelSupportsBuiltinSearchPluginControl: modelSupportsBuiltinSearchPluginControl
        )
    }

    func normalizeContextCacheControls() {
        ChatControlNormalizationSupport.normalizeContextCacheControls(
            controls: &controls,
            supportsContextCacheControl: supportsContextCacheControl,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            supportsContextCacheStrategy: supportsContextCacheStrategy,
            supportsContextCacheTTL: supportsContextCacheTTL,
            providerType: providerType
        )
    }

    func normalizeMCPToolsControls() {
        ChatControlNormalizationSupport.normalizeMCPToolsControls(
            controls: &controls,
            supportsMCPToolsControl: supportsMCPToolsControl
        )
    }

    func normalizeAnthropicMaxTokens() {
        ChatControlNormalizationSupport.normalizeAnthropicMaxTokens(
            controls: &controls,
            supportsReasoningControl: supportsReasoningControl,
            providerType: providerType
        )
    }

    func normalizeImageGenerationControls() {
        ChatControlNormalizationSupport.normalizeImageGenerationControls(
            controls: &controls,
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            supportsCurrentModelImageSizeControl: supportsCurrentModelImageSizeControl,
            supportedCurrentModelImageSizes: supportedCurrentModelImageSizes,
            supportedCurrentModelImageAspectRatios: supportedCurrentModelImageAspectRatios,
            lowerModelID: lowerModelID
        )
    }

    func normalizeOpenAIImageControls(_ controls: inout OpenAIImageGenerationControls) {
        ChatControlNormalizationSupport.normalizeOpenAIImageControls(
            &controls,
            lowerModelID: lowerModelID
        )
    }

    func normalizeVideoGenerationControls() {
        ChatControlNormalizationSupport.normalizeVideoGenerationControls(
            controls: &controls,
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            lowerModelID: lowerModelID
        )
    }
}
