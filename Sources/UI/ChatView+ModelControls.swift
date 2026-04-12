import SwiftUI
import SwiftData

// MARK: - Model Controls

extension ChatView {

    var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: conversationEntity.providerID)
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

    func openCodexSessionSettingsEditor() {
        codexWorkingDirectoryDraft = codexWorkingDirectory ?? ""
        codexWorkingDirectoryDraftError = nil
        codexSandboxModeDraft = controls.codexSandboxMode
        codexPersonalityDraft = controls.codexPersonality
        showingCodexSessionSettingsSheet = true
    }

    func openClaudeManagedAgentSessionSettingsEditor() {
        let providerDefaults = providers.first(where: { $0.id == conversationEntity.providerID })
        claudeManagedProviderDefaultAgentID = providerDefaults?.claudeManagedDefaultAgentID ?? ""
        claudeManagedProviderDefaultEnvironmentID = providerDefaults?.claudeManagedDefaultEnvironmentID ?? ""
        claudeManagedProviderDefaultAgentDisplayName = providerDefaults?.claudeManagedDefaultAgentDisplayName ?? ""
        claudeManagedProviderDefaultEnvironmentDisplayName = providerDefaults?.claudeManagedDefaultEnvironmentDisplayName ?? ""

        claudeManagedAgentIDDraft = controls.claudeManagedAgentID ?? claudeManagedProviderDefaultAgentID
        claudeManagedEnvironmentIDDraft = controls.claudeManagedEnvironmentID ?? claudeManagedProviderDefaultEnvironmentID
        claudeManagedAgentDisplayNameDraft = resolvedClaudeManagedAgentDisplayName(
            for: conversationEntity.providerID,
            threadModelID: conversationEntity.modelID,
            threadControls: controls
        )
        claudeManagedEnvironmentDisplayNameDraft = resolvedClaudeManagedEnvironmentDisplayName(
            for: conversationEntity.providerID,
            threadControls: controls
        ) ?? claudeManagedProviderDefaultEnvironmentDisplayName
        claudeManagedAgentSettingsDraftError = nil
        showingClaudeManagedAgentSessionSettingsSheet = true
        Task { await refreshClaudeManagedAgentSessionResources() }
    }

    @MainActor
    func applyClaudeManagedAgentSelection(_ descriptor: ClaudeManagedAgentDescriptor) {
        guard providerType == .claudeManagedAgents else { return }

        let currentResolvedControls = resolvedClaudeManagedControls(
            for: conversationEntity.providerID,
            threadControls: controls
        )
        var updatedControls = controls
        updatedControls.claudeManagedAgentID = descriptor.id
        updatedControls.claudeManagedAgentDisplayName = descriptor.name
        updatedControls.claudeManagedAgentModelID = descriptor.modelID
        updatedControls.claudeManagedAgentModelDisplayName = descriptor.modelDisplayName

        let updatedResolvedControls = resolvedClaudeManagedControls(
            for: conversationEntity.providerID,
            threadControls: updatedControls
        )

        if activeModelThread != nil,
           (updatedResolvedControls.claudeManagedAgentID != currentResolvedControls.claudeManagedAgentID
               || updatedResolvedControls.claudeManagedEnvironmentID != currentResolvedControls.claudeManagedEnvironmentID) {
            updatedControls.clearClaudeManagedAgentSessionState()
            if let activeModelThread {
                clearClaudeManagedAgentSessionPersistence(for: activeModelThread)
            }
        }

        controls = updatedControls

        if let activeModelThread,
           providerType(forProviderID: activeModelThread.providerID) == .claudeManagedAgents {
            activeModelThread.modelID = managedAgentSyntheticModelID(
                providerID: activeModelThread.providerID,
                controls: updatedResolvedControls
            )
            synchronizeLegacyConversationModelFields(with: activeModelThread)
        }

        persistControlsToConversation()
    }

    func pickCodexWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory to send as Codex `cwd`."

        if let existing = normalizedCodexWorkingDirectoryPath(from: codexWorkingDirectoryDraft) {
            panel.directoryURL = URL(fileURLWithPath: existing, isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        codexWorkingDirectoryDraft = selectedURL.path
        codexWorkingDirectoryDraftError = nil
    }

    func applyCodexSessionSettingsDraft() {
        switch ChatEditorDraftSupport.applyCodexSessionSettingsDraft(
            workingDirectoryDraft: codexWorkingDirectoryDraft,
            sandboxModeDraft: codexSandboxModeDraft,
            personalityDraft: codexPersonalityDraft,
            controls: controls
        ) {
        case .success(let result):
            controls = result.controls
            persistControlsToConversation()
            codexWorkingDirectoryDraft = result.normalizedPath ?? ""
            codexWorkingDirectoryDraftError = nil
            showingCodexSessionSettingsSheet = false
        case .failure(let error):
            codexWorkingDirectoryDraftError = error.localizedDescription
        }
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
            let currentResolvedControls = resolvedClaudeManagedControls(
                for: conversationEntity.providerID,
                threadControls: controls
            )
            var resolvedControls = updatedControls
            let updatedResolvedControls = resolvedClaudeManagedControls(
                for: conversationEntity.providerID,
                threadControls: updatedControls
            )
            if activeModelThread != nil,
               (updatedResolvedControls.claudeManagedAgentID != currentResolvedControls.claudeManagedAgentID
                   || updatedResolvedControls.claudeManagedEnvironmentID != currentResolvedControls.claudeManagedEnvironmentID) {
                resolvedControls.clearClaudeManagedAgentSessionState()
                if let activeModelThread {
                    clearClaudeManagedAgentSessionPersistence(for: activeModelThread)
                }
            }
            controls = resolvedControls
            if let activeModelThread,
               providerType(forProviderID: activeModelThread.providerID) == .claudeManagedAgents {
                let syntheticModelID = managedAgentSyntheticModelID(
                    providerID: activeModelThread.providerID,
                    controls: resolvedClaudeManagedControls(
                        for: activeModelThread.providerID,
                        threadControls: resolvedControls
                    )
                )
                activeModelThread.modelID = syntheticModelID
                synchronizeLegacyConversationModelFields(with: activeModelThread)
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

        guard let providerEntity = providers.first(where: { $0.id == conversationEntity.providerID }),
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

            claudeManagedAvailableAgents = try await agents.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            claudeManagedAvailableEnvironments = try await environments.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

            if claudeManagedAgentDisplayNameDraft.isEmpty,
               let selected = claudeManagedAvailableAgents.first(where: { $0.id == claudeManagedAgentIDDraft }) {
                claudeManagedAgentDisplayNameDraft = selected.name
            }
            if claudeManagedEnvironmentDisplayNameDraft.isEmpty,
               let selected = claudeManagedAvailableEnvironments.first(where: { $0.id == claudeManagedEnvironmentIDDraft }) {
                claudeManagedEnvironmentDisplayNameDraft = selected.name
            }

            claudeManagedAgentSettingsDraftError = nil
        } catch {
            if force || (claudeManagedAvailableAgents.isEmpty && claudeManagedAvailableEnvironments.isEmpty) {
                claudeManagedAgentSettingsDraftError = error.localizedDescription
            }
        }
    }

    func resolveCodexInteraction(_ item: PendingCodexInteraction, response: CodexInteractionResponse) {
        Task {
            await item.request.resolve(response)
        }
        pendingCodexInteractions.removeAll { $0.id == item.id }
    }

    func resolveAgentApproval(_ item: PendingAgentApproval, choice: AgentApprovalChoice) {
        Task {
            await item.request.resolve(choice)
        }
        pendingAgentApprovals.removeAll { $0.id == item.id }
    }

    func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        ChatEditorDraftSupport.normalizedCodexWorkingDirectoryPath(from: raw)
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
