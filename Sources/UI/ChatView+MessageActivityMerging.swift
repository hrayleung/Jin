import Foundation

// MARK: - Message Activity Merging

extension ChatView {

    @MainActor
    func mergeSearchActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [SearchActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        entity.searchActivitiesData = ChatMessageActivityMergeSupport.mergedSearchActivities(
            existingData: entity.searchActivitiesData,
            newActivities: newActivities
        )
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    func mergeAgentToolActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [CodexToolActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        entity.agentToolActivitiesData = ChatMessageActivityMergeSupport.mergedAgentToolActivities(
            existingData: entity.agentToolActivitiesData,
            newActivities: newActivities
        )
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }
}
