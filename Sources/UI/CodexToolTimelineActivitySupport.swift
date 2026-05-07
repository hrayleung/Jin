import Foundation

extension CodexToolTimelineSupport {
    static func entries(for activities: [CodexToolActivity]) -> [Entry] {
        activities.map { Entry(activity: $0) }
    }

    static func executionStatus(for activity: CodexToolActivity) -> ToolCallExecutionStatus {
        CodexToolActivityStatusSupport.executionStatus(for: activity.status)
    }

    static func counts(for entries: [Entry]) -> ActivityCounts {
        ActivityCounts(
            running: entries.filter { $0.executionStatus == .running }.count,
            succeeded: entries.filter { $0.executionStatus == .success }.count,
            failed: entries.filter { $0.executionStatus == .error }.count
        )
    }

    static func entryAnimationSignature(for entries: [Entry]) -> String {
        entries
            .map { "\($0.id):\($0.executionStatus)" }
            .joined(separator: "|")
    }
}
