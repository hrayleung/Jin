import Foundation

struct StreamingUIFlushBuffer {
    private(set) var streamedCharacterCount = 0
    private(set) var lastFlushUptime: TimeInterval = 0
    private var pendingTextDelta = ""
    private var pendingThinkingDelta = ""
    private var pendingToolCalls: [ToolCall]?
    private var pendingSearchActivities: [SearchActivity] = []
    private var pendingCodeExecutionActivities: [CodeExecutionActivity] = []
    private var hasFlushed = false

    var currentFlushInterval: TimeInterval {
        // Coalesce more aggressively as streams grow so MainActor artifact/markdown
        // work stays bounded under high token rates.
        switch streamedCharacterCount {
        case 0..<4_000:
            return 0.08
        case 4_000..<12_000:
            return 0.10
        case 12_000..<40_000:
            return 0.14
        default:
            return 0.18
        }
    }

    private var hasPendingDeltas: Bool {
        !pendingTextDelta.isEmpty
            || !pendingThinkingDelta.isEmpty
            || pendingToolCalls != nil
            || !pendingSearchActivities.isEmpty
            || !pendingCodeExecutionActivities.isEmpty
    }

    mutating func appendText(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingTextDelta.append(delta)
        streamedCharacterCount += delta.count
    }

    mutating func appendThinking(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingThinkingDelta.append(delta)
        streamedCharacterCount += delta.count
    }

    /// Queue the latest tool-call snapshot for the next UI flush (replaces prior pending).
    mutating func setPendingToolCalls(_ calls: [ToolCall]) {
        pendingToolCalls = calls
    }

    mutating func appendSearchActivity(_ activity: SearchActivity) {
        if let index = pendingSearchActivities.firstIndex(where: { $0.id == activity.id }) {
            pendingSearchActivities[index] = pendingSearchActivities[index].merged(with: activity)
        } else {
            pendingSearchActivities.append(activity)
        }
    }

    mutating func appendCodeExecutionActivity(_ activity: CodeExecutionActivity) {
        if let index = pendingCodeExecutionActivities.firstIndex(where: { $0.id == activity.id }) {
            pendingCodeExecutionActivities[index] = pendingCodeExecutionActivities[index].merged(with: activity)
        } else {
            pendingCodeExecutionActivities.append(activity)
        }
    }

    mutating func flushIfNeeded(force: Bool = false, now: TimeInterval) -> StreamingUIFlush? {
        guard force || now - lastFlushUptime >= currentFlushInterval else { return nil }
        guard force || hasPendingDeltas else { return nil }

        lastFlushUptime = now
        let flush = StreamingUIFlush(
            textDelta: pendingTextDelta,
            thinkingDelta: pendingThinkingDelta,
            isFirstFlush: !hasFlushed,
            force: force,
            toolCalls: pendingToolCalls,
            searchActivities: pendingSearchActivities,
            codeExecutionActivities: pendingCodeExecutionActivities
        )
        pendingTextDelta = ""
        pendingThinkingDelta = ""
        pendingToolCalls = nil
        pendingSearchActivities = []
        pendingCodeExecutionActivities = []
        hasFlushed = true
        return flush
    }
}
