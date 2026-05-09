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

    /// Threads that should render as their own column in the message stage.
    ///
    /// A thread earns a panel by having received messages. We deliberately
    /// decouple this from `selectedThreads` (which controls the next-send
    /// recipients) so that toggling a tab on for a future send doesn't
    /// summon an empty panel from the past.
    ///
    /// When no thread has messages yet (a brand-new conversation), fall back
    /// to a single panel anchored on the active thread so the user has a
    /// stage to type into. Once the first message is sent, the populated set
    /// takes over.
    static func panelThreads(
        from sortedThreads: [ConversationModelThreadEntity],
        allMessages: [MessageEntity],
        activeThread: ConversationModelThreadEntity?
    ) -> [ConversationModelThreadEntity] {
        let threadIDsWithMessages: Set<UUID> = Set(allMessages.compactMap(\.contextThreadID))

        let withMessages = sortedThreads.filter { threadIDsWithMessages.contains($0.id) }
        if !withMessages.isEmpty {
            return withMessages
        }

        if let activeThread {
            return [activeThread]
        }
        if let firstThread = sortedThreads.first {
            return [firstThread]
        }
        return []
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
