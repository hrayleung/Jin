import Foundation

/// Render-mode policy for messages in long conversations.
///
/// HISTORY: this used to auto-collapse "memory-intensive" assistant messages
/// older than the last `ChatView.smartLongChatExpandedTailCount` once a
/// conversation crossed `smartLongChatCollapseThreshold` — a guard from the
/// WebView era (the `.fullWeb` naming survives), when every rendered message
/// kept a live WKWebView resident and long conversations genuinely exhausted
/// memory. The recycling `NSTableView` timeline made that guard obsolete:
/// off-screen rows are never realized at all, so resident view cost is
/// bounded by the viewport regardless of conversation length — and the
/// collapsed preview cards actively degraded old conversations (raw `**`
/// markers in the preview text, prose mislabeled as code, an Expand tap to
/// read anything).
///
/// The policy now never auto-collapses. The `.collapsedPreview` render mode
/// and its UI remain for messages that explicitly prefer it, but nothing is
/// demoted by age anymore.
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
        return .fullWeb
    }

    static func expandedMessageIDs(byExpanding messageID: UUID, from expandedIDs: Set<UUID>) -> Set<UUID> {
        var next = expandedIDs
        next.insert(messageID)
        return next
    }
}
