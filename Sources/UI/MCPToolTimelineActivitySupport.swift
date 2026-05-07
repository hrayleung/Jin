import Foundation

extension MCPToolTimelineSupport {
    static func entries(
        toolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult]
    ) -> [Entry] {
        toolCalls.map { call in
            Entry(call: call, result: toolResultsByCallID[call.id])
        }
    }

    static func status(for result: ToolResult?) -> ToolCallExecutionStatus {
        guard let result else { return .running }
        return result.isError ? .error : .success
    }

    static func counts(for entries: [Entry]) -> StatusCounts {
        StatusCounts(
            running: entries.filter { $0.status == .running }.count,
            succeeded: entries.filter { $0.status == .success }.count,
            failed: entries.filter { $0.status == .error }.count
        )
    }

    static func totalDurationSeconds(for entries: [Entry]) -> Double? {
        let durations = entries.compactMap { $0.result?.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    static func entryAnimationSignature(for entries: [Entry]) -> String {
        entries
            .map { entry in
                "\(entry.id):\(statusToken(for: entry.status))"
            }
            .joined(separator: "|")
    }

    static func statusToken(for status: ToolCallExecutionStatus) -> String {
        switch status {
        case .running: return "running"
        case .success: return "success"
        case .error: return "error"
        }
    }
}
