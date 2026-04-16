import SwiftUI
import SwiftData

// MARK: - Control Normalization & Web Search

extension ChatView {


    var supportsAnthropicDynamicFiltering: Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerType,
            modelID: conversationEntity.modelID
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
            providerType: providerType
        ) {
        case .success(let draft):
            controls.contextCache = draft
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
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
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

    func refreshExtensionCredentialsStatus() async {
        let status = ChatConversationStateSupport.resolveExtensionCredentialStatus()

        await MainActor.run {
            mistralOCRConfigured = status.mistralOCRConfigured
            mineruOCRConfigured = status.mineruOCRConfigured
            deepSeekOCRConfigured = status.deepSeekOCRConfigured
            firecrawlOCRConfigured = status.firecrawlOCRConfigured
            textToSpeechConfigured = status.textToSpeechConfigured
            speechToTextConfigured = status.speechToTextConfigured
            webSearchPluginConfigured = status.webSearchPluginConfigured

            mistralOCRPluginEnabled = status.mistralOCRPluginEnabled
            mineruOCRPluginEnabled = status.mineruOCRPluginEnabled
            deepSeekOCRPluginEnabled = status.deepSeekOCRPluginEnabled
            firecrawlOCRPluginEnabled = status.firecrawlOCRPluginEnabled
            textToSpeechPluginEnabled = status.textToSpeechPluginEnabled
            speechToTextPluginEnabled = status.speechToTextPluginEnabled
            webSearchPluginEnabled = status.webSearchPluginEnabled

            if !status.textToSpeechPluginEnabled {
                ttsPlaybackManager.stop()
            }
            if !status.speechToTextPluginEnabled {
                speechToTextManager.cancelAndCleanup()
            }
        }
    }

    func currentSpeechToTextTranscriptionConfig() async throws -> SpeechToTextManager.TranscriptionConfig {
        try SpeechPluginConfigFactory.speechToTextConfig()
    }

    func toggleSpeakAssistantMessage(_ messageEntity: MessageEntity, text: String) {
        Task { @MainActor in
            guard textToSpeechPluginEnabled else { return }

            let provider = try? SpeechPluginConfigFactory.currentTTSProvider()

            do {
                let config = try SpeechPluginConfigFactory.textToSpeechConfig()
                let context = TextToSpeechPlaybackManager.PlaybackContext(
                    conversationID: conversationEntity.id,
                    conversationTitle: conversationEntity.title,
                    textPreview: String(text.prefix(80))
                )
                ttsPlaybackManager.toggleSpeak(
                    messageID: messageEntity.id,
                    text: text,
                    config: config,
                    context: context,
                    onError: { error in
                        errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                        showingError = true
                    }
                )
            } catch {
                errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                showingError = true
            }
        }
    }

    func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
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

    func setReasoningOff() {
        ChatReasoningSupport.setReasoningOff(
            controls: &controls,
            reasoningMustRemainEnabled: reasoningMustRemainEnabled,
            selectedReasoningConfig: selectedReasoningConfig,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    func setReasoningOn() {
        ChatReasoningSupport.setReasoningOn(
            controls: &controls,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    func setReasoningEffort(_ effort: ReasoningEffort) {
        guard providerType != .anthropic else {
            openThinkingBudgetEditor()
            return
        }

        ChatReasoningSupport.setReasoningEffort(
            controls: &controls,
            effort: effort,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl
        )
        persistControlsToConversation()
    }

    func setAnthropicThinkingBudget(_ budgetTokens: Int) {
        ChatReasoningSupport.setAnthropicThinkingBudget(
            controls: &controls,
            budgetTokens: budgetTokens,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    var thinkingBudgetDraftInt: Int? {
        ChatEditorDraftSupport.thinkingBudgetDraftInt(from: thinkingBudgetDraft)
    }

    var anthropicUsesAdaptiveThinking: Bool {
        ChatReasoningSupport.anthropicUsesAdaptiveThinking(
            providerType: providerType,
            modelID: conversationEntity.modelID
        )
    }

    var anthropicUsesEffortMode: Bool {
        ChatReasoningSupport.anthropicUsesEffortMode(
            providerType: providerType,
            modelID: conversationEntity.modelID
        )
    }

    var supportsAnthropicThinkingDisplayControl: Bool {
        ChatReasoningSupport.supportsAnthropicThinkingDisplayControl(
            providerType: providerType,
            modelID: conversationEntity.modelID
        )
    }

    var anthropicEffortBinding: Binding<ReasoningEffort> {
        Binding(
            get: {
                ChatReasoningSupport.normalizedAnthropicEffort(
                    currentEffort: controls.reasoning?.effort,
                    defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high
                )
            },
            set: { newValue in
                ChatReasoningSupport.setAnthropicEffort(
                    controls: &controls,
                    newValue: newValue,
                    anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
                    modelID: conversationEntity.modelID,
                    defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
                    defaultBudget: anthropicDefaultBudgetTokens
                )
                persistControlsToConversation()
            }
        )
    }

    var anthropicDefaultBudgetTokens: Int {
        selectedReasoningConfig?.defaultBudget ?? 1024
    }

    var maxTokensDraftInt: Int? {
        ChatEditorDraftSupport.maxTokensDraftInt(from: maxTokensDraft)
    }

    var isThinkingBudgetDraftValid: Bool {
        ChatEditorDraftSupport.isThinkingBudgetDraftValid(
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft,
            currentMaxTokens: controls.maxTokens
        )
    }

    var thinkingBudgetValidationWarning: String? {
        ChatEditorDraftSupport.thinkingBudgetValidationWarning(
            providerType: providerType,
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            modelID: conversationEntity.modelID,
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft,
            currentMaxTokens: controls.maxTokens
        )
    }

    func openThinkingBudgetEditor() {
        let prepared = ChatEditorDraftSupport.prepareThinkingBudgetEditorDraft(
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            budgetTokens: controls.reasoning?.budgetTokens ?? selectedReasoningConfig?.defaultBudget,
            defaultBudget: anthropicDefaultBudgetTokens,
            providerType: providerType,
            requestedMaxTokens: controls.maxTokens,
            modelID: conversationEntity.modelID
        )
        thinkingBudgetDraft = prepared.thinkingBudgetDraft
        maxTokensDraft = prepared.maxTokensDraft
        anthropicThinkingDisplayDraft = ChatReasoningSupport.resolvedAnthropicThinkingDisplay(
            currentDisplay: controls.reasoning?.anthropicThinkingDisplay,
            providerType: providerType,
            modelID: conversationEntity.modelID
        )
        showingThinkingBudgetSheet = true
    }

    func applyThinkingBudgetDraft() {
        let resolvedMaxTokensDraft = ChatReasoningSupport.applyThinkingBudgetDraft(
            controls: &controls,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            anthropicUsesEffortMode: anthropicUsesEffortMode,
            anthropicThinkingDisplay: supportsAnthropicThinkingDisplayControl ? anthropicThinkingDisplayDraft : nil,
            budgetTokens: thinkingBudgetDraftInt,
            maxTokens: maxTokensDraftInt,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        if providerType == .anthropic, let resolvedMaxTokensDraft {
            maxTokensDraft = resolvedMaxTokensDraft
        }
        persistControlsToConversation()
    }

    func normalizeAnthropicReasoningAndMaxTokens() {
        ChatReasoningSupport.normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: providerType,
            modelID: conversationEntity.modelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
    }

    func setReasoningSummary(_ summary: ReasoningSummary) {
        ChatReasoningSupport.setReasoningSummary(
            controls: &controls,
            summary: summary,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .medium
        )
        persistControlsToConversation()
    }

    func updateReasoning(_ mutate: (inout ReasoningControls) -> Void) {
        ChatReasoningSupport.updateReasoning(
            controls: &controls,
            mutate: mutate
        )
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

        if supportsReasoningControl, let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                normalizeEffortBasedReasoning(config: reasoningConfig)
            case .budget:
                normalizeBudgetBasedReasoning(config: reasoningConfig)
            case .toggle:
                normalizeToggleBasedReasoning()
            case .none:
                controls.reasoning = nil
            }
        } else if !supportsReasoningControl {
            controls.reasoning = nil
        }

        enforceReasoningAlwaysOnIfRequired()
    }

    func normalizeEffortBasedReasoning(config: ModelReasoningConfig) {
        if providerType != .anthropic,
           controls.reasoning?.enabled == true,
           controls.reasoning?.effort == nil {
            updateReasoning { $0.effort = config.defaultEffort ?? .medium }
        }

        if providerType != .anthropic {
            controls.reasoning?.budgetTokens = nil
        }
        if supportsReasoningSummaryControl,
           controls.reasoning?.enabled == true,
           (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
           controls.reasoning?.summary == nil {
            controls.reasoning?.summary = .auto
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
    }

    func normalizeBudgetBasedReasoning(config: ModelReasoningConfig) {
        if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
            updateReasoning { $0.budgetTokens = config.defaultBudget ?? 2048 }
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.summary = nil
    }

    func normalizeToggleBasedReasoning() {
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.budgetTokens = nil
        controls.reasoning?.summary = nil
    }

    func enforceReasoningAlwaysOnIfRequired() {
        guard reasoningMustRemainEnabled else { return }
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        } else {
            controls.reasoning?.enabled = true
        }

        if selectedReasoningConfig?.type == .effort,
           controls.reasoning?.effort == nil || controls.reasoning?.effort == ReasoningEffort.none {
            controls.reasoning?.effort = selectedReasoningConfig?.defaultEffort ?? .medium
        }
    }

    func normalizeReasoningEffortLimits() {
        guard supportsReasoningControl else { return }

        if let effort = controls.reasoning?.effort {
            controls.reasoning?.effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                effort,
                for: providerType,
                modelID: conversationEntity.modelID
            )
        }

        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
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
            isMiniMaxM2FamilyModel: isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID),
            fireworksReasoningHistoryOptions: fireworksReasoningHistoryOptions
        )
    }

    func normalizeAnthropicProviderSpecific() {
        ChatControlNormalizationSupport.normalizeAnthropicProviderSpecific(
            controls: &controls,
            providerType: providerType,
            modelID: conversationEntity.modelID
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
        if modelSupportsWebSearchControl {
            if controls.webSearch?.enabled == true {
                ensureValidWebSearchDefaultsIfEnabled()
            }
        } else {
            controls.webSearch = nil
        }
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

    var builtinSearchIncludeRawBinding: Binding<Bool> {

        Binding(
            get: {
                controls.searchPlugin?.includeRawContent ?? false
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.includeRawContent = newValue ? true : nil
                persistControlsToConversation()
            }
        )
    }

    var builtinSearchFetchPageBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.fetchPageContent ?? settings.jinaReadPages
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.fetchPageContent = newValue
                persistControlsToConversation()
            }
        )
    }

    var builtinSearchFirecrawlExtractBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.firecrawlExtractContent ?? settings.firecrawlExtractContent
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.firecrawlExtractContent = newValue
                persistControlsToConversation()
            }
        )
    }


    func webSearchSourceBinding(_ source: WebSearchSource) -> Binding<Bool> {
        Binding(
            get: {
                Set(controls.webSearch?.sources ?? []).contains(source)
            },
            set: { isOn in
                var set = Set(controls.webSearch?.sources ?? [])
                if isOn {
                    set.insert(source)
                } else {
                    set.remove(source)
                }
                controls.webSearch?.sources = Array(set).sorted { $0.rawValue < $1.rawValue }
                persistControlsToConversation()
            }
        )
    }
}
