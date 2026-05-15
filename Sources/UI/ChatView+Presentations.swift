import SwiftUI

extension ChatView {

    func chatPresentations<Content: View>(_ content: Content) -> some View {
        content
            .alert("Couldn't complete chat action", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: supportedAttachmentImportTypes,
                allowsMultipleSelection: true
            ) { result in
                handleAttachmentImport(result)
            }
            .sheet(isPresented: $isExpandedComposerPresented, onDismiss: {
                guard !isComposerHidden else { return }
                DispatchQueue.main.async {
                    isComposerFocused = true
                }
            }) {
                expandedComposerSheet
            }
            .sheet(isPresented: $showingThinkingBudgetSheet) {
                ThinkingBudgetSheetView(
                    usesAdaptiveThinking: anthropicUsesAdaptiveThinking,
                    usesEffortMode: anthropicUsesEffortMode,
                    modelID: activeModelID,
                    modelMaxOutputTokens: AnthropicModelLimits.maxOutputTokens(for: activeModelID),
                    supportedEffortLevels: availableReasoningEffortLevels,
                    thinkingBudgetDraft: $thinkingBudgetDraft,
                    maxTokensDraft: $maxTokensDraft,
                    supportsThinkingDisplayControl: supportsAnthropicThinkingDisplayControl,
                    thinkingDisplaySelection: $anthropicThinkingDisplayDraft,
                    effortSelection: anthropicEffortBinding,
                    isValid: isThinkingBudgetDraftValid,
                    validationWarning: thinkingBudgetValidationWarning,
                    onCancel: { showingThinkingBudgetSheet = false },
                    onSave: {
                        applyThinkingBudgetDraft()
                        showingThinkingBudgetSheet = false
                    }
                )
            }
            .sheet(isPresented: $showingCodeExecutionSheet) {
                CodeExecutionSheetView(
                    draft: $codeExecutionDraft,
                    openAIUseExistingContainer: $codeExecutionOpenAIUseExistingContainer,
                    openAIFileIDsDraft: $codeExecutionOpenAIFileIDsDraft,
                    draftError: $codeExecutionDraftError,
                    providerType: providerType,
                    isValid: isCodeExecutionDraftValid,
                    onCancel: { showingCodeExecutionSheet = false },
                    onSave: { applyCodeExecutionDraft() }
                )
            }
            .sheet(isPresented: $showingContextCacheSheet) {
                ContextCacheSheetView(
                    draft: $contextCacheDraft,
                    ttlPreset: $contextCacheTTLPreset,
                    customTTLDraft: $contextCacheCustomTTLDraft,
                    minTokensDraft: $contextCacheMinTokensDraft,
                    advancedExpanded: $contextCacheAdvancedExpanded,
                    draftError: $contextCacheDraftError,
                    providerType: providerType,
                    supportsExplicitMode: supportsExplicitContextCacheMode,
                    supportsStrategy: supportsContextCacheStrategy,
                    supportsTTL: supportsContextCacheTTL,
                    supportsAdvancedOptions: contextCacheSupportsAdvancedOptions,
                    summaryText: contextCacheSummaryText,
                    guidanceText: contextCacheGuidanceText,
                    isValid: isContextCacheDraftValid,
                    onCancel: { showingContextCacheSheet = false },
                    onSave: { applyContextCacheDraft() }
                )
            }
            .sheet(isPresented: $showingAnthropicWebSearchSheet) {
                AnthropicWebSearchSheetView(
                    domainMode: $anthropicWebSearchDomainMode,
                    allowedDomainsDraft: $anthropicWebSearchAllowedDomainsDraft,
                    blockedDomainsDraft: $anthropicWebSearchBlockedDomainsDraft,
                    locationDraft: $anthropicWebSearchLocationDraft,
                    draftError: $anthropicWebSearchDraftError,
                    onCancel: { showingAnthropicWebSearchSheet = false },
                    onSave: { applyAnthropicWebSearchDraft() }
                )
            }
            .sheet(isPresented: $showingGoogleMapsSheet) {
                GoogleMapsSheetView(
                    draft: $googleMapsDraft,
                    latitudeDraft: $googleMapsLatitudeDraft,
                    longitudeDraft: $googleMapsLongitudeDraft,
                    languageCodeDraft: $googleMapsLanguageCodeDraft,
                    draftError: $googleMapsDraftError,
                    providerType: providerType,
                    isValid: isGoogleMapsDraftValid,
                    onCancel: { showingGoogleMapsSheet = false },
                    onSave: { applyGoogleMapsDraft() }
                )
            }
            .sheet(isPresented: $showingImageGenerationSheet) {
                ImageGenerationSheetView(
                    draft: $imageGenerationDraft,
                    seedDraft: $imageGenerationSeedDraft,
                    compressionQualityDraft: $imageGenerationCompressionQualityDraft,
                    draftError: $imageGenerationDraftError,
                    providerType: providerType,
                    supportsImageSizeControl: supportsCurrentModelImageSizeControl,
                    supportedAspectRatios: supportedCurrentModelImageAspectRatios,
                    supportedImageSizes: supportedCurrentModelImageSizes,
                    isValid: isImageGenerationDraftValid,
                    onCancel: { showingImageGenerationSheet = false },
                    onSave: { applyImageGenerationDraft() }
                )
            }
            .sheet(isPresented: $showingOpenAIImageCustomSizeSheet) {
                OpenAIImageCustomSizeSheetView(
                    modelID: openAIImageCustomSizeTargetModelID.isEmpty ? lowerModelID : openAIImageCustomSizeTargetModelID,
                    currentSize: controls.openaiImageGeneration?.size,
                    onCancel: { dismissOpenAIImageCustomSizeSheet() },
                    onSave: { size in
                        handleOpenAIImageCustomSizeSave(size)
                    }
                )
            }
            .sheet(isPresented: $showingClaudeManagedAgentSessionSettingsSheet) {
                ClaudeManagedAgentSessionSettingsSheetView(
                    agentIDDraft: $claudeManagedAgentIDDraft,
                    environmentIDDraft: $claudeManagedEnvironmentIDDraft,
                    agentDisplayNameDraft: $claudeManagedAgentDisplayNameDraft,
                    environmentDisplayNameDraft: $claudeManagedEnvironmentDisplayNameDraft,
                    draftError: $claudeManagedAgentSettingsDraftError,
                    availableAgents: claudeManagedAvailableAgents,
                    availableEnvironments: claudeManagedAvailableEnvironments,
                    isRefreshingResources: isRefreshingClaudeManagedSessionResources,
                    providerDefaultAgentID: claudeManagedProviderDefaultAgentID,
                    providerDefaultEnvironmentID: claudeManagedProviderDefaultEnvironmentID,
                    providerDefaultAgentDisplayName: claudeManagedProviderDefaultAgentDisplayName,
                    providerDefaultEnvironmentDisplayName: claudeManagedProviderDefaultEnvironmentDisplayName,
                    onRefreshResources: {
                        Task { await refreshClaudeManagedAgentSessionResources(force: true) }
                    },
                    onUseProviderDefaults: useClaudeManagedProviderDefaultsForSettingsDraft,
                    onCancel: { showingClaudeManagedAgentSessionSettingsSheet = false },
                    onSave: { applyClaudeManagedAgentSessionSettingsDraft() }
                )
            }
            .sheet(item: activeManagedAgentInteractionBinding) { item in
                ManagedAgentInteractionSheetView(request: item.request) { response in
                    resolveManagedAgentInteraction(item, response: response)
                }
            }
    }
}
