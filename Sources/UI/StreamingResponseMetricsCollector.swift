import Foundation

/// Captures response-level metrics while streaming a single assistant turn.
struct StreamingResponseMetricsCollector {
    private var requestStartedAt: Date?
    private var firstOutputAt: Date?
    private var streamEndedAt: Date?
    private var usage: Usage?

    mutating func begin(at date: Date = Date()) {
        requestStartedAt = date
        firstOutputAt = nil
        streamEndedAt = nil
        usage = nil
    }

    mutating func observe(event: StreamEvent, at date: Date = Date()) {
        switch event {
        case .contentDelta(let part):
            markOutputIfNeeded(for: part, at: date)
        case .thinkingDelta(let delta):
            markOutputIfNeeded(for: delta, at: date)
        case .messageEnd(let usage):
            if let usage {
                self.usage = usage
            }
        default:
            break
        }
    }

    mutating func end(at date: Date = Date()) {
        streamEndedAt = date
    }

    var metrics: ResponseMetrics? {
        guard let requestStartedAt else { return nil }

        let ttft = firstOutputAt.map { max(0, $0.timeIntervalSince(requestStartedAt)) }
        let duration = streamEndedAt.map { max(0, $0.timeIntervalSince(requestStartedAt)) }

        guard usage != nil || ttft != nil || duration != nil else { return nil }
        return ResponseMetrics(
            usage: usage,
            timeToFirstTokenSeconds: ttft,
            durationSeconds: duration
        )
    }

    private mutating func markOutputIfNeeded(for part: ContentPart, at date: Date) {
        switch part {
        case .text(let text) where !text.isEmpty:
            markFirstOutput(at: date)
        case .image, .video:
            markFirstOutput(at: date)
        default:
            break
        }
    }

    private mutating func markOutputIfNeeded(for delta: ThinkingDelta, at date: Date) {
        switch delta {
        case .thinking(let textDelta, _):
            if !textDelta.isEmpty {
                markFirstOutput(at: date)
            }
        case .redacted:
            break
        }
    }

    private mutating func markFirstOutput(at date: Date) {
        guard firstOutputAt == nil else { return }
        firstOutputAt = date
    }
}
