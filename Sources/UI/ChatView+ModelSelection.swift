import SwiftUI
import SwiftData

// MARK: - Model Selection

extension ChatView {

    @MainActor
    func setProvider(_ providerID: String) {
        guard providerID != conversationEntity.providerID else { return }
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        let models = provider.selectableModels

        clearClaudeManagedAgentSessionPersistence(for: conversationEntity)
        conversationEntity.providerID = providerID

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            if let managedModelID = models.first?.id {
                conversationEntity.modelID = managedModelID
            }
            normalizeControlsForCurrentSelection()
            try? modelContext.save()
            return
        }

        guard !models.isEmpty else { return }

        if let preferredID = preferredModelID(in: models, providerID: providerID) {
            conversationEntity.modelID = preferredID
        } else {
            conversationEntity.modelID = models.first?.id ?? conversationEntity.modelID
        }

        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    @MainActor
    func setModel(_ modelID: String) {
        let resolvedModelID = canonicalModelID(for: conversationEntity.providerID, modelID: modelID)
        guard resolvedModelID != canonicalModelID(for: conversationEntity.providerID, modelID: conversationEntity.modelID) else {
            return
        }
        if providerType(forProviderID: conversationEntity.providerID) != .claudeManagedAgents {
            clearClaudeManagedAgentSessionPersistence(for: conversationEntity)
        }
        conversationEntity.modelID = resolvedModelID
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    @MainActor
    func setProviderAndModel(providerID: String, modelID: String) {
        let resolvedModelID = canonicalModelID(for: providerID, modelID: modelID)

        if providerID != conversationEntity.providerID {
            clearClaudeManagedAgentSessionPersistence(for: conversationEntity)
        }
        conversationEntity.providerID = providerID
        conversationEntity.modelID = resolvedModelID
        conversationEntity.updatedAt = Date()
        normalizeControlsForCurrentSelection()
        persistControlsToConversation()
    }

    func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        ChatModelSelectionSupport.preferredModelID(
            in: models,
            providerID: providerID,
            providers: providers,
            geminiPreferredModelOrder: Self.geminiPreferredModelOrder
        )
    }

    @ViewBuilder
    func modelPickerPopoverContent(
        includeManagedAgentSelection: Bool,
        onSelect: @escaping (String, String) -> Void
    ) -> some View {
        ModelPickerPopover(
            favoritesStore: favoriteModelsStore,
            providers: providers,
            selectedProviderID: activeProviderID,
            selectedModelID: activeModelID,
            managedAgentContext: includeManagedAgentSelection ? currentManagedAgentPickerContext : nil,
            onSelect: onSelect
        )
    }

    var currentManagedAgentPickerContext: ModelPickerPopover.ManagedAgentContext? {
        guard providerType == .claudeManagedAgents,
              let currentProvider else { return nil }

        let resolvedControls = resolvedClaudeManagedControls(
            for: activeProviderID,
            threadControls: controls
        )

        return ModelPickerPopover.ManagedAgentContext(
            provider: currentProvider,
            selectedAgentID: resolvedControls.claudeManagedAgentID,
            availableAgents: resolvedClaudeManagedAgentOptions(
                for: activeProviderID,
                threadControls: controls
            ),
            isRefreshing: isRefreshingClaudeManagedSessionResources,
            onRefresh: {
                Task { await refreshClaudeManagedAgentSessionResources() }
            },
            onOpenSettings: {
                openClaudeManagedAgentSessionSettingsEditor()
            },
            onSelectAgent: { descriptor in
                applyClaudeManagedAgentSelection(descriptor)
                isModelPickerPresented = false
            }
        )
    }
}
