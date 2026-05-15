import SwiftUI
import SwiftData

// MARK: - Model Controls

extension ChatView {

    var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == activeProviderID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: activeProviderID)
    }

    func openImageGenerationEditor() {
        let prepared = ChatEditorDraftSupport.prepareImageGenerationEditorDraft(
            current: controls.imageGeneration,
            supportedAspectRatios: supportedCurrentModelImageAspectRatios,
            supportedImageSizes: supportedCurrentModelImageSizes
        )
        imageGenerationDraft = prepared.draft
        imageGenerationSeedDraft = prepared.seedDraft
        imageGenerationCompressionQualityDraft = prepared.compressionQualityDraft
        imageGenerationDraftError = nil
        showingImageGenerationSheet = true
    }

    func openClaudeManagedAgentSessionSettingsEditor() {
        let providerDefaults = claudeManagedProviderDefaults()
        applyClaudeManagedProviderDefaults(providerDefaults)

        let draft = ChatClaudeManagedAgentSessionSupport.preparedSettingsDraft(
            controls: controls,
            providerDefaults: providerDefaults,
            resolvedAgentDisplayName: resolvedClaudeManagedAgentDisplayName(
                for: activeProviderID,
                threadModelID: activeModelID,
                threadControls: controls
            ),
            resolvedEnvironmentDisplayName: resolvedClaudeManagedEnvironmentDisplayName(
                for: activeProviderID,
                threadControls: controls
            )
        )
        applyClaudeManagedSettingsDraft(draft)
        claudeManagedAgentSettingsDraftError = nil
        showingClaudeManagedAgentSessionSettingsSheet = true
        Task { await refreshClaudeManagedAgentSessionResources() }
    }

    func useClaudeManagedProviderDefaultsForSettingsDraft() {
        applyClaudeManagedSettingsDraft(
            ChatClaudeManagedAgentSessionSupport.settingsDraftUsingProviderDefaults(
                claudeManagedProviderDefaultsFromDraftState()
            )
        )
        claudeManagedAgentSettingsDraftError = nil
    }

    private func claudeManagedProviderDefaults() -> ChatClaudeManagedAgentSessionSupport.ProviderDefaults {
        let providerDefaults = providers.first(where: { $0.id == activeProviderID })
        return ChatClaudeManagedAgentSessionSupport.ProviderDefaults(
            agentID: providerDefaults?.claudeManagedDefaultAgentID,
            environmentID: providerDefaults?.claudeManagedDefaultEnvironmentID,
            agentDisplayName: providerDefaults?.claudeManagedDefaultAgentDisplayName,
            environmentDisplayName: providerDefaults?.claudeManagedDefaultEnvironmentDisplayName
        )
    }

    private func claudeManagedProviderDefaultsFromDraftState() -> ChatClaudeManagedAgentSessionSupport.ProviderDefaults {
        ChatClaudeManagedAgentSessionSupport.ProviderDefaults(
            agentID: claudeManagedProviderDefaultAgentID,
            environmentID: claudeManagedProviderDefaultEnvironmentID,
            agentDisplayName: claudeManagedProviderDefaultAgentDisplayName,
            environmentDisplayName: claudeManagedProviderDefaultEnvironmentDisplayName
        )
    }

    private func applyClaudeManagedProviderDefaults(_ providerDefaults: ChatClaudeManagedAgentSessionSupport.ProviderDefaults) {
        claudeManagedProviderDefaultAgentID = providerDefaults.agentID
        claudeManagedProviderDefaultEnvironmentID = providerDefaults.environmentID
        claudeManagedProviderDefaultAgentDisplayName = providerDefaults.agentDisplayName
        claudeManagedProviderDefaultEnvironmentDisplayName = providerDefaults.environmentDisplayName
    }

    private func claudeManagedSettingsDraftFromState() -> ChatClaudeManagedAgentSessionSupport.SettingsDraft {
        ChatClaudeManagedAgentSessionSupport.SettingsDraft(
            agentID: claudeManagedAgentIDDraft,
            environmentID: claudeManagedEnvironmentIDDraft,
            agentDisplayName: claudeManagedAgentDisplayNameDraft,
            environmentDisplayName: claudeManagedEnvironmentDisplayNameDraft
        )
    }

    private func applyClaudeManagedSettingsDraft(_ draft: ChatClaudeManagedAgentSessionSupport.SettingsDraft) {
        claudeManagedAgentIDDraft = draft.agentID
        claudeManagedEnvironmentIDDraft = draft.environmentID
        claudeManagedAgentDisplayNameDraft = draft.agentDisplayName
        claudeManagedEnvironmentDisplayNameDraft = draft.environmentDisplayName
    }

    private func fillClaudeManagedSettingsDraftResourceNamesIfNeeded() {
        applyClaudeManagedSettingsDraft(
            ChatClaudeManagedAgentSessionSupport.settingsDraftFillingResourceNames(
                claudeManagedSettingsDraftFromState(),
                availableAgents: claudeManagedAvailableAgents,
                availableEnvironments: claudeManagedAvailableEnvironments
            )
        )
    }

    @MainActor
    func applyClaudeManagedAgentSelection(_ descriptor: ClaudeManagedAgentDescriptor) {
        guard providerType == .claudeManagedAgents else { return }

        let update = ChatClaudeManagedAgentSessionSupport.controlsApplyingAgentSelection(
            descriptor,
            currentControls: controls,
            resolveControls: { controls in
                resolvedClaudeManagedControls(
                    for: activeProviderID,
                    threadControls: controls
                )
            }
        )

        if activeModelThread != nil, update.didChangeIdentity {
            if let activeModelThread {
                clearClaudeManagedAgentSessionPersistence(for: activeModelThread)
            }
        }

        controls = update.controls

        if let activeModelThread,
           providerType(forProviderID: activeModelThread.providerID) == .claudeManagedAgents {
            activeModelThread.modelID = managedAgentSyntheticModelID(
                providerID: activeModelThread.providerID,
                controls: update.resolvedControls
            )
            setActiveThread(activeModelThread)
        }

        persistControlsToConversation()
    }

    func applyClaudeManagedAgentSessionSettingsDraft() {
        switch ChatEditorDraftSupport.applyClaudeManagedAgentSessionSettingsDraft(
            agentIDDraft: claudeManagedAgentIDDraft,
            environmentIDDraft: claudeManagedEnvironmentIDDraft,
            agentDisplayNameDraft: claudeManagedAgentDisplayNameDraft,
            environmentDisplayNameDraft: claudeManagedEnvironmentDisplayNameDraft,
            controls: controls
        ) {
        case .success(let updatedControls):
            let update = ChatClaudeManagedAgentSessionSupport.controlUpdate(
                currentControls: controls,
                updatedControls: updatedControls,
                resolveControls: { controls in
                    resolvedClaudeManagedControls(
                        for: activeProviderID,
                        threadControls: controls
                    )
                }
            )
            if activeModelThread != nil, update.didChangeIdentity {
                if let activeModelThread {
                    clearClaudeManagedAgentSessionPersistence(for: activeModelThread)
                }
            }
            controls = update.controls
            if let activeModelThread,
               providerType(forProviderID: activeModelThread.providerID) == .claudeManagedAgents {
                let syntheticModelID = managedAgentSyntheticModelID(
                    providerID: activeModelThread.providerID,
                    controls: resolvedClaudeManagedControls(
                        for: activeModelThread.providerID,
                        threadControls: update.controls
                    )
                )
                activeModelThread.modelID = syntheticModelID
                setActiveThread(activeModelThread)
            }
            persistControlsToConversation()
            claudeManagedAgentSettingsDraftError = nil
            showingClaudeManagedAgentSessionSettingsSheet = false
        case .failure(let error):
            claudeManagedAgentSettingsDraftError = error.localizedDescription
        }
    }

    @MainActor
    func refreshClaudeManagedAgentSessionResources(force: Bool = false) async {
        guard providerType == .claudeManagedAgents else { return }
        guard !isRefreshingClaudeManagedSessionResources else { return }

        guard let providerEntity = providers.first(where: { $0.id == activeProviderID }),
              let config = try? providerEntity.toDomain(),
              let adapter = try? await ProviderManager().createAdapter(for: config) as? ClaudeManagedAgentsAdapter else {
            if force {
                claudeManagedAgentSettingsDraftError = "Failed to initialize Claude Managed Agents provider."
            }
            return
        }

        let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            if force {
                claudeManagedAgentSettingsDraftError = "Enter an Anthropic API key in provider settings first."
            }
            return
        }

        isRefreshingClaudeManagedSessionResources = true
        defer { isRefreshingClaudeManagedSessionResources = false }

        do {
            async let agents = adapter.listAgents()
            async let environments = adapter.listEnvironments()

            let fetchedAgents = try await agents
            let fetchedEnvironments = try await environments
            claudeManagedAvailableAgents = ChatClaudeManagedAgentSessionSupport.sortedAgents(fetchedAgents)
            claudeManagedAvailableEnvironments = ChatClaudeManagedAgentSessionSupport.sortedEnvironments(fetchedEnvironments)

            fillClaudeManagedSettingsDraftResourceNamesIfNeeded()

            claudeManagedAgentSettingsDraftError = nil
        } catch {
            if force || (claudeManagedAvailableAgents.isEmpty && claudeManagedAvailableEnvironments.isEmpty) {
                claudeManagedAgentSettingsDraftError = error.localizedDescription
            }
        }
    }

    func resolveManagedAgentInteraction(_ item: PendingManagedAgentInteraction, response: ManagedAgentInteractionResponse) {
        Task {
            await item.request.resolve(response)
        }
        pendingManagedAgentInteractions.removeAll { $0.id == item.id }
    }

    var isImageGenerationDraftValid: Bool {
        ChatEditorDraftSupport.isImageGenerationDraftValid(
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft
        )
    }

    @discardableResult
    func applyImageGenerationDraft() -> Bool {
        switch ChatEditorDraftSupport.applyImageGenerationDraft(
            draft: imageGenerationDraft,
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft,
            supportsCurrentModelImageSizeControl: supportsCurrentModelImageSizeControl,
            supportedCurrentModelImageSizes: supportedCurrentModelImageSizes,
            supportedCurrentModelImageAspectRatios: supportedCurrentModelImageAspectRatios,
            providerType: providerType
        ) {
        case .success(let draft):
            controls.imageGeneration = draft
            persistControlsToConversation()
            imageGenerationDraftError = nil
            return true
        case .failure(let error):
            imageGenerationDraftError = error.localizedDescription
            return false
        }
    }

    func openContextCacheEditor() {
        let prepared = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: controls.contextCache,
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
        contextCacheDraft = prepared.draft
        contextCacheTTLPreset = prepared.ttlPreset
        contextCacheCustomTTLDraft = prepared.customTTLDraft
        contextCacheMinTokensDraft = prepared.minTokensDraft
        contextCacheAdvancedExpanded = prepared.advancedExpanded
        contextCacheDraftError = nil
        showingContextCacheSheet = true
    }
}
