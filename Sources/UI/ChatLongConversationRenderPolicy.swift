import Foundation

enum ChatLongConversationRenderPolicy {
    static func effectiveRenderMode(
        index: Int,
        message: MessageRenderItem,
        totalMessageCount: Int,
        visibleMessageCount: Int,
        expandedIDs: Set<UUID>
    ) -> MessageRenderMode {
        if message.preferredRenderMode == .nativeText {
            return .nativeText
        }

        guard shouldCollapse(
            index: index,
            message: message,
            totalMessageCount: totalMessageCount,
            visibleMessageCount: visibleMessageCount,
            expandedIDs: expandedIDs
        ) else {
            return .fullWeb
        }

        return .collapsedPreview
    }

    static func expandedMessageIDs(byExpanding messageID: UUID, from expandedIDs: Set<UUID>) -> Set<UUID> {
        var next = expandedIDs
        next.insert(messageID)
        return next
    }

    private static func shouldCollapse(
        index: Int,
        message: MessageRenderItem,
        totalMessageCount: Int,
        visibleMessageCount: Int,
        expandedIDs: Set<UUID>
    ) -> Bool {
        guard message.isAssistant,
              message.isMemoryIntensiveAssistantContent,
              message.collapsedPreview != nil,
              totalMessageCount > ChatView.smartLongChatCollapseThreshold,
              visibleMessageCount > ChatView.smartLongChatExpandedTailCount,
              index < max(0, visibleMessageCount - ChatView.smartLongChatExpandedTailCount),
              !expandedIDs.contains(message.id) else {
            return false
        }

        return true
    }
}
