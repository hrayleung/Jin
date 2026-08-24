import Combine
import Foundation

/// In-flight tool results that persisted assistant cards observe directly.
///
/// Publishing these through `ChatRenderCacheController.version` / the
/// timeline content epoch remounts every resident `NSHostingView` (including
/// the streaming orb) on each MCP/builtin result. Cards subscribe here
/// instead so the table apply can stay idle.
@MainActor
final class ChatLiveToolResultStore: ObservableObject {
    @Published private(set) var resultsByCallID: [String: ToolResult] = [:]

    /// Collapse the empty live Generating row while the last assistant still
    /// owns in-flight tools. Written from the table `apply` so the streaming
    /// cell can observe the flag without a `rootView` remount.
    @Published private(set) var suppressIdleStreamingPlaceholder = false

    /// Conversation-level streaming flag observed by persisted assistant
    /// cards. Identity mutations do not reconfigure survivors, so this must
    /// travel on the same store as live tool results or Connecting stays up
    /// after the turn has finished.
    @Published private(set) var isConversationStreaming = false

    /// The persisted assistant that temporarily owns the turn's one live orb
    /// while the empty streaming row is suppressed.
    @Published private(set) var streamingActivityOwnerMessageID: UUID?

    func setSuppressIdleStreamingPlaceholder(_ suppress: Bool) {
        guard suppressIdleStreamingPlaceholder != suppress else { return }
        suppressIdleStreamingPlaceholder = suppress
    }

    func applyTimelinePresentation(
        isConversationStreaming: Bool,
        activityOwnerMessageID: UUID?,
        suppressIdleStreamingPlaceholder: Bool
    ) {
        if self.isConversationStreaming != isConversationStreaming {
            self.isConversationStreaming = isConversationStreaming
        }
        if streamingActivityOwnerMessageID != activityOwnerMessageID {
            streamingActivityOwnerMessageID = activityOwnerMessageID
        }
        setSuppressIdleStreamingPlaceholder(suppressIdleStreamingPlaceholder)
    }

    func replaceAll(_ results: [String: ToolResult]) {
        guard resultsByCallID != results else { return }
        resultsByCallID = results
    }

    func upsert(_ result: ToolResult) {
        if resultsByCallID[result.toolCallID] == result { return }
        resultsByCallID[result.toolCallID] = result
    }

    func clear() {
        guard !resultsByCallID.isEmpty else { return }
        resultsByCallID = [:]
    }
}
