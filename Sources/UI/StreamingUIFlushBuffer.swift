import Foundation

struct StreamingUIFlush: Equatable {
    let textDelta: String
    let thinkingDelta: String
    let isFirstFlush: Bool
    let force: Bool
}

struct StreamingUIFlushBuffer {
    private(set) var streamedCharacterCount = 0
    private(set) var lastFlushUptime: TimeInterval = 0
    private var pendingTextDelta = ""
    private var pendingThinkingDelta = ""
    private var hasFlushed = false

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

    mutating func flushIfNeeded(force: Bool = false, now: TimeInterval) -> StreamingUIFlush? {
        guard force || now - lastFlushUptime >= currentFlushInterval else { return nil }
        guard force || !pendingTextDelta.isEmpty || !pendingThinkingDelta.isEmpty else { return nil }

        lastFlushUptime = now
        let flush = StreamingUIFlush(
            textDelta: pendingTextDelta,
            thinkingDelta: pendingThinkingDelta,
            isFirstFlush: !hasFlushed,
            force: force
        )
        pendingTextDelta = ""
        pendingThinkingDelta = ""
        hasFlushed = true
        return flush
    }
}
