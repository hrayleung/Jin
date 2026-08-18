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

    func setSuppressIdleStreamingPlaceholder(_ suppress: Bool) {
        guard suppressIdleStreamingPlaceholder != suppress else { return }
        suppressIdleStreamingPlaceholder = suppress
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
