import SwiftUI
import SwiftData

// MARK: - Thread Management & Model Selection

extension ChatView {

    var currentModelName: String {
        if providerType == .claudeManagedAgents {
            return resolvedClaudeManagedAgentDisplayName(
                for: conversationEntity.providerID,
                threadModelID: conversationEntity.modelID,
                threadControls: controls
            )
        }
        return ChatThreadSupport.currentModelName(
            providerID: conversationEntity.providerID,
            modelID: conversationEntity.modelID,
            providers: providers,
            providerType: providerType,
            resolveModelInfo: { modelID, providerEntity, providerType in
                resolvedModelInfo(
                    for: modelID,
                    providerEntity: providerEntity,
                    providerType: providerType
                )
            }
        )
    }

    var currentProvider: ProviderConfigEntity? {
        ChatThreadSupport.currentProvider(
            for: conversationEntity.providerID,
            in: providers
        )
    }

    var currentProviderIconID: String? {
        ChatThreadSupport.providerIconID(
            for: conversationEntity.providerID,
            in: providers
        )
    }

    func providerIconID(for providerID: String) -> String? {
        ChatThreadSupport.providerIconID(
            for: providerID,
            in: providers
        )
    }

    func modelName(id modelID: String, providerID: String) -> String {
        if providerType(forProviderID: providerID) == .claudeManagedAgents {
            let threadControls = sortedModelThreads.first(where: {
                $0.providerID == providerID && canonicalModelID(for: providerID, modelID: $0.modelID) == canonicalModelID(for: providerID, modelID: modelID)
            }).flatMap(storedGenerationControls(for:))
            return resolvedClaudeManagedAgentDisplayName(
                for: providerID,
                threadModelID: modelID,
                threadControls: threadControls
            )
        }

        return ChatThreadSupport.modelName(
            modelID: modelID,
            providerID: providerID,
            providers: providers,
            resolveModelInfo: { modelID, providerEntity, providerType in
                resolvedModelInfo(
                    for: modelID,
                    providerEntity: providerEntity,
                    providerType: providerType
                )
            }
        )
    }

    func isActiveThread(_ thread: ConversationModelThreadEntity) -> Bool {
        activeModelThread?.id == thread.id
    }

    func toggleThreadSelection(_ thread: ConversationModelThreadEntity) {
        ChatThreadSupport.toggleThreadSelection(
            thread: thread,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            activeThread: activeModelThread,
            modelContext: modelContext,
            activateThread: { thread in
                activateThread(thread)
            },
            rebuildMessageCaches: {
                rebuildMessageCaches()
            }
        )
    }

    func synchronizeLegacyConversationModelFields(with thread: ConversationModelThreadEntity) {
        ChatThreadSupport.synchronizeLegacyConversationModelFields(
            conversationEntity: conversationEntity,
            activeThreadID: &activeThreadID,
            thread: thread
        )
    }

    func activateThread(_ thread: ConversationModelThreadEntity) {
        guard conversationEntity.modelThreads.contains(where: { $0.id == thread.id }) else { return }
        let isAlreadyActiveThread = activeModelThread?.id == thread.id
        let isLegacySelectionSynchronized =
            conversationEntity.activeThreadID == thread.id
            && conversationEntity.providerID == thread.providerID
            && conversationEntity.modelID == thread.modelID
            && thread.isSelected
        // Message selection in the multi-model timeline can bubble up as a row tap.
        // Ignore no-op reactivation so that selection does not churn caches or UI state.
        guard !(isAlreadyActiveThread && isLegacySelectionSynchronized) else {
            return
        }

        thread.lastActivatedAt = Date()
        thread.updatedAt = Date()
        thread.isSelected = true
        synchronizeLegacyConversationModelFields(with: thread)
        canonicalizeThreadModelIDIfNeeded(thread)
        loadControlsFromConversation()
        normalizeControlsForCurrentSelection()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    func activateThread(by threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        activateThread(thread)
    }

    func removeModelThread(_ thread: ConversationModelThreadEntity) {
        ChatThreadSupport.removeModelThread(
            thread: thread,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            activeThreadID: activeThreadID,
            streamingStore: streamingStore,
            modelContext: modelContext,
            rebuildMessageCaches: {
                rebuildMessageCaches()
            },
            activateThread: { thread in
                activateThread(thread)
            }
        )
    }

    func addOrActivateThread(providerID: String, modelID: String) {
        let resolvedModelID: String
        if providerType(forProviderID: providerID) == .claudeManagedAgents,
           modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedModelID = managedAgentSyntheticModelID(
                providerID: providerID,
                controls: defaultClaudeManagedAgentControls(for: providerID)
            )
        } else {
            resolvedModelID = modelID
        }

        ChatThreadSupport.addOrActivateThread(
            providerID: providerID,
            modelID: resolvedModelID,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            activateThread: { thread in
                activateThread(thread)
            },
            showError: { message in
                errorMessage = message
                showingError = true
            }
        )
    }

    // MARK: - Model Selection

    var availableModels: [ModelInfo] {
        currentProvider?.enabledModels ?? []
    }

    func isFullySupportedModel(modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    func setProvider(_ providerID: String) {
        ChatModelSelectionSupport.setProvider(
            providerID: providerID,
            activeThread: activeModelThread,
            providers: providers,
            modelContext: modelContext,
            clearCodexThreadPersistence: { thread in
                clearCodexThreadPersistence(for: thread)
            },
            clearClaudeManagedAgentSessionPersistence: { thread in
                clearClaudeManagedAgentSessionPersistence(for: thread)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            },
            preferredModelID: { models, providerID in
                preferredModelID(in: models, providerID: providerID)
            }
        )
    }

    func setModel(_ modelID: String) {
        ChatModelSelectionSupport.setModel(
            modelID: modelID,
            activeThread: activeModelThread,
            modelContext: modelContext,
            providerTypeForProviderID: { providerID in
                providerType(forProviderID: providerID)
            },
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            clearClaudeManagedAgentSessionPersistence: { thread in
                clearClaudeManagedAgentSessionPersistence(for: thread)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            }
        )
    }

    func setProviderAndModel(providerID: String, modelID: String) {
        ChatModelSelectionSupport.setProviderAndModel(
            providerID: providerID,
            modelID: modelID,
            activeThread: activeModelThread,
            sortedThreads: sortedModelThreads,
            clearCodexThreadPersistence: { thread in
                clearCodexThreadPersistence(for: thread)
            },
            clearClaudeManagedAgentSessionPersistence: { thread in
                clearClaudeManagedAgentSessionPersistence(for: thread)
            },
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            addOrActivateThread: { providerID, modelID in
                addOrActivateThread(providerID: providerID, modelID: modelID)
            },
            activateThread: { thread in
                activateThread(thread)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            },
            persistControlsToConversation: {
                persistControlsToConversation()
            }
        )
    }

    func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        ChatModelSelectionSupport.preferredModelID(
            in: models,
            providerID: providerID,
            providers: providers,
            geminiPreferredModelOrder: Self.geminiPreferredModelOrder,
            isFireworksModelID: { modelID, canonicalID in
                isFireworksModelID(modelID, canonicalID: canonicalID)
            }
        )
    }
}
