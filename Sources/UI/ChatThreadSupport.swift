import Foundation
import SwiftData

enum ChatThreadSupport {
    static func sortedThreads(in threads: [ConversationModelThreadEntity]) -> [ConversationModelThreadEntity] {
        threads.sorted { lhs, rhs in
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    static func activeThread(
        in threads: [ConversationModelThreadEntity],
        preferredID: UUID?
    ) -> ConversationModelThreadEntity? {
        guard !threads.isEmpty else { return nil }

        if let preferredID,
           let thread = threads.first(where: { $0.id == preferredID }) {
            return thread
        }

        let selected = threads.filter(\.isSelected)
        if let latest = selected.max(by: { $0.lastActivatedAt < $1.lastActivatedAt }) {
            return latest
        }

        return threads.first
    }

    static func selectedThreads(
        from sortedThreads: [ConversationModelThreadEntity],
        activeThread: ConversationModelThreadEntity?
    ) -> [ConversationModelThreadEntity] {
        let selected = sortedThreads.filter(\.isSelected)
        let base = selected.isEmpty ? sortedThreads.prefix(1).map { $0 } : selected
        guard let activeThread else { return base }

        if base.contains(where: { $0.id == activeThread.id }) {
            return base
        }
        return base + [activeThread]
    }

    static func secondaryToolbarThreads(
        from sortedThreads: [ConversationModelThreadEntity],
        activeThread: ConversationModelThreadEntity?
    ) -> [ConversationModelThreadEntity] {
        guard let activeThread else { return sortedThreads }
        return sortedThreads.filter { $0.id != activeThread.id }
    }

    static func currentProvider(
        for providerID: String,
        in providers: [ProviderConfigEntity]
    ) -> ProviderConfigEntity? {
        providers.first(where: { $0.id == providerID })
    }

    static func providerIconID(
        for providerID: String,
        in providers: [ProviderConfigEntity]
    ) -> String? {
        currentProvider(for: providerID, in: providers)?.resolvedProviderIconID
    }

    static func modelName(
        modelID: String,
        providerID: String,
        providers: [ProviderConfigEntity],
        resolveModelInfo: (String, ProviderConfigEntity?, ProviderType?) -> ModelInfo?
    ) -> String {
        let providerEntity = currentProvider(for: providerID, in: providers)
        let providerType = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) }
        return resolveModelInfo(modelID, providerEntity, providerType)?.name ?? modelID
    }

    static func currentModelName(
        providerID: String,
        modelID: String,
        providers: [ProviderConfigEntity],
        providerType: ProviderType?,
        resolveModelInfo: (String, ProviderConfigEntity?, ProviderType?) -> ModelInfo?
    ) -> String {
        let providerEntity = currentProvider(for: providerID, in: providers)
        return resolveModelInfo(modelID, providerEntity, providerType)?.name ?? modelID
    }

    static func headerToolbarThreads(
        secondaryThreads: [ConversationModelThreadEntity],
        sortedThreadCount: Int,
        providerIconID: (String) -> String?,
        modelName: (String, String) -> String,
        isActiveThread: (ConversationModelThreadEntity) -> Bool
    ) -> [ChatHeaderToolbarThread] {
        let isRemovable = sortedThreadCount > 1

        return secondaryThreads.map { thread in
            ChatHeaderToolbarThread(
                id: thread.id,
                providerIconID: providerIconID(thread.providerID),
                title: String(modelName(thread.modelID, thread.providerID).prefix(22)),
                isSelected: thread.isSelected,
                isActive: isActiveThread(thread),
                isRemovable: isRemovable
            )
        }
    }

    static func synchronizeLegacyConversationModelFields(
        conversationEntity: ConversationEntity,
        activeThreadID: inout UUID?,
        thread: ConversationModelThreadEntity
    ) {
        if conversationEntity.providerID != thread.providerID {
            conversationEntity.providerID = thread.providerID
        }
        if conversationEntity.modelID != thread.modelID {
            conversationEntity.modelID = thread.modelID
        }
        if conversationEntity.modelConfigData != thread.modelConfigData {
            conversationEntity.modelConfigData = thread.modelConfigData
        }
        if conversationEntity.activeThreadID != thread.id {
            conversationEntity.activeThreadID = thread.id
        }
        if activeThreadID != thread.id {
            activeThreadID = thread.id
        }
    }

    @MainActor
    static func toggleThreadSelection(
        thread: ConversationModelThreadEntity,
        conversationEntity: ConversationEntity,
        sortedThreads: [ConversationModelThreadEntity],
        activeThread: ConversationModelThreadEntity?,
        modelContext: ModelContext,
        activateThread: (ConversationModelThreadEntity) -> Void,
        rebuildMessageCaches: () -> Void
    ) {
        guard let index = conversationEntity.modelThreads.firstIndex(where: { $0.id == thread.id }) else { return }
        if activeThread?.id == thread.id {
            activateThread(conversationEntity.modelThreads[index])
            return
        }

        let selectedCount = sortedThreads.filter(\.isSelected).count
        let isCurrentlySelected = conversationEntity.modelThreads[index].isSelected

        if isCurrentlySelected && selectedCount <= 1 {
            activateThread(conversationEntity.modelThreads[index])
            return
        }

        conversationEntity.modelThreads[index].isSelected.toggle()
        conversationEntity.modelThreads[index].updatedAt = Date()
        conversationEntity.updatedAt = Date()

        if conversationEntity.modelThreads[index].isSelected {
            activateThread(conversationEntity.modelThreads[index])
            return
        }

        rebuildMessageCaches()
        try? modelContext.save()
    }

    @MainActor
    static func removeModelThread(
        thread: ConversationModelThreadEntity,
        conversationEntity: ConversationEntity,
        sortedThreads: [ConversationModelThreadEntity],
        activeThreadID: UUID?,
        streamingStore: ConversationStreamingStore,
        modelContext: ModelContext,
        rebuildMessageCaches: () -> Void,
        activateThread: (ConversationModelThreadEntity) -> Void
    ) {
        guard sortedThreads.count > 1 else { return }
        let removedThreadID = thread.id
        let activeBeforeRemovalID = activeThreadID ?? conversationEntity.activeThreadID
        let removedWasActive = activeBeforeRemovalID == removedThreadID
        streamingStore.cancel(conversationID: conversationEntity.id, threadID: removedThreadID)
        streamingStore.endSession(conversationID: conversationEntity.id, threadID: removedThreadID)

        for message in conversationEntity.messages where message.contextThreadID == removedThreadID {
            modelContext.delete(message)
        }
        conversationEntity.messages.removeAll { $0.contextThreadID == removedThreadID }

        if let index = conversationEntity.modelThreads.firstIndex(where: { $0.id == removedThreadID }) {
            let threadEntity = conversationEntity.modelThreads[index]
            conversationEntity.modelThreads.remove(at: index)
            modelContext.delete(threadEntity)
        }

        let updatedSortedThreads = Self.sortedThreads(in: conversationEntity.modelThreads)
        if removedWasActive {
            if let replacement = updatedSortedThreads.first(where: \.isSelected) ?? updatedSortedThreads.first {
                activateThread(replacement)
            }
        } else if let currentActiveID = activeBeforeRemovalID,
                  !updatedSortedThreads.contains(where: { $0.id == currentActiveID }),
                  let fallback = updatedSortedThreads.first {
            activateThread(fallback)
        }

        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    @MainActor
    static func addOrActivateThread(
        providerID: String,
        modelID: String,
        conversationEntity: ConversationEntity,
        sortedThreads: [ConversationModelThreadEntity],
        canonicalModelID: (String, String) -> String,
        activateThread: (ConversationModelThreadEntity) -> Void,
        showError: (String) -> Void
    ) {
        let resolvedModelID = canonicalModelID(providerID, modelID)
        if let existing = sortedThreads.first(where: {
            $0.providerID == providerID && canonicalModelID($0.providerID, $0.modelID) == resolvedModelID
        }) {
            existing.isSelected = true
            activateThread(existing)
            return
        }

        guard sortedThreads.count < 3 else {
            showError("A chat can include up to 3 models.")
            return
        }

        let encodedControls = (try? JSONEncoder().encode(GenerationControls())) ?? Data()
        let nextOrder = (sortedThreads.map(\.displayOrder).max() ?? -1) + 1
        let thread = ConversationModelThreadEntity(
            providerID: providerID,
            modelID: resolvedModelID,
            modelConfigData: encodedControls,
            displayOrder: nextOrder,
            isSelected: true,
            isPrimary: false
        )
        thread.conversation = conversationEntity
        conversationEntity.modelThreads.append(thread)
        conversationEntity.updatedAt = Date()
        activateThread(thread)
    }
}
