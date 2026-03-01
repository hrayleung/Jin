import Foundation

/// Per-response performance and token metrics shown in the chat UI.
struct ResponseMetrics: Codable, Equatable, Sendable {
    let usage: Usage?
    let timeToFirstTokenSeconds: Double?
    let durationSeconds: Double?

    init(
        usage: Usage?,
        timeToFirstTokenSeconds: Double?,
        durationSeconds: Double?
    ) {
        self.usage = usage
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.durationSeconds = durationSeconds
    }

    var outputTokensPerSecond: Double? {
        guard let usage, let durationSeconds, durationSeconds > 0 else { return nil }
        return Double(usage.outputTokens) / durationSeconds
    }
}
