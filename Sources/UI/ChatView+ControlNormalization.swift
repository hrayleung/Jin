import SwiftData
import SwiftUI

// MARK: - Control Persistence & Normalization

extension ChatView {

    func ensureModelThreadsInitializedIfNeeded() {
        ChatConversationStateSupport.ensureModelThreadsInitializedIfNeeded(
            conversationEntity: conversationEntity,
            activeThreadID: &activeThreadID,
            modelContext: modelContext,
            activeModelThread: { activeModelThread },
            sortedModelThreads: { sortedModelThreads }
        )
    }

    func syncActiveThreadSelection() {
        ChatConversationStateSupport.syncActiveThreadSelection(
            activeModelThread: activeModelThread,
            sortedModelThreads: sortedModelThreads,
            setActiveThread: { thread in
                setActiveThread(thread)
            }
        )
    }

    func loadControlsFromConversation() {
        ensureModelThreadsInitializedIfNeeded()
        syncActiveThreadSelection()

        if let activeThread = activeModelThread {
            canonicalizeThreadModelIDIfNeeded(activeThread)
        }

        controls = ChatConversationStateSupport.loadControlsFromConversation(
            conversationEntity: conversationEntity,
            activeThread: activeModelThread
        )
        normalizeControlsForCurrentSelection()
    }

    func persistControlsToConversation() {
        do {
            try ChatConversationStateSupport.persistControlsToConversation(
                controls: controls,
                activeThread: activeModelThread,
                storedGenerationControls: { thread in
                    storedGenerationControls(for: thread)
                },
                conversationEntity: conversationEntity,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
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
        normalizeCodexProviderSpecific()
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

    func normalizeCodexProviderSpecific() {
        ChatControlNormalizationSupport.normalizeCodexProviderSpecific(
            controls: &controls,
            providerType: providerType
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
