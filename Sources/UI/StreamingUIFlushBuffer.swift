import Foundation

struct StreamingUIFlush: Equatable {
    let textDelta: String
    let thinkingDelta: String
    let isFirstFlush: Bool
    let force: Bool
    /// `nil` means no tool-call change this flush.
    let toolCalls: [ToolCall]?
    let searchActivities: [SearchActivity]
    let codeExecutionActivities: [CodeExecutionActivity]

    static func == (lhs: StreamingUIFlush, rhs: StreamingUIFlush) -> Bool {
        lhs.textDelta == rhs.textDelta
            && lhs.thinkingDelta == rhs.thinkingDelta
            && lhs.isFirstFlush == rhs.isFirstFlush
            && lhs.force == rhs.force
            && lhs.toolCalls?.map(\.id) == rhs.toolCalls?.map(\.id)
            && lhs.searchActivities.map(\.id) == rhs.searchActivities.map(\.id)
            && lhs.codeExecutionActivities.map(\.id) == rhs.codeExecutionActivities.map(\.id)
    }
}

struct StreamingUIFlushBuffer {
    private(set) var streamedCharacterCount = 0
    private(set) var lastFlushUptime: TimeInterval = 0
    private var pendingTextDelta = ""
    private var pendingThinkingDelta = ""
    private var pendingToolCalls: [ToolCall]?
    private var pendingSearchActivities: [SearchActivity] = []
    private var pendingCodeExecutionActivities: [CodeExecutionActivity] = []
    private var hasFlushed = false
    private var hasFlushedActivity = false

    var currentFlushInterval: TimeInterval {
        switch streamedCharacterCount {
        case 0..<4_000:
            return 0.08
        case 4_000..<12_000:
            return 0.10
        default:
            return 0.12
        }
    }

    private var hasPendingTextOrThinking: Bool {
        !pendingTextDelta.isEmpty || !pendingThinkingDelta.isEmpty
    }

    private var hasPendingActivity: Bool {
        pendingToolCalls != nil
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

    mutating func setToolCalls(_ calls: [ToolCall]) {
        pendingToolCalls = calls
    }

    mutating func upsertSearchActivity(_ activity: SearchActivity) {
        if let index = pendingSearchActivities.firstIndex(where: { $0.id == activity.id }) {
            pendingSearchActivities[index] = pendingSearchActivities[index].merged(with: activity)
        } else {
            pendingSearchActivities.append(activity)
        }
    }

    mutating func upsertCodeExecutionActivity(_ activity: CodeExecutionActivity) {
        if let index = pendingCodeExecutionActivities.firstIndex(where: { $0.id == activity.id }) {
            pendingCodeExecutionActivities[index] = pendingCodeExecutionActivities[index].merged(with: activity)
        } else {
            pendingCodeExecutionActivities.append(activity)
        }
    }

    mutating func flushIfNeeded(force: Bool = false, now: TimeInterval) -> StreamingUIFlush? {
        let hasPending = hasPendingTextOrThinking || hasPendingActivity
        // First activity of a buffer lifetime can flush immediately so tool chrome appears without waiting.
        let isImmediateFirstActivity = hasPendingActivity && !hasFlushedActivity

        if !force {
            guard hasPending else { return nil }
            if !isImmediateFirstActivity, now - lastFlushUptime < currentFlushInterval {
                return nil
            }
        }

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
        if flush.toolCalls != nil
            || !flush.searchActivities.isEmpty
            || !flush.codeExecutionActivities.isEmpty
        {
            hasFlushedActivity = true
        }
        return flush
    }
}
