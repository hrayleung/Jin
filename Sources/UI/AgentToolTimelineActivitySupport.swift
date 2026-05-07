import Foundation

extension AgentToolTimelineSupport {
    static func counts(for activities: [CodexToolActivity]) -> ActivityCounts {
        ActivityCounts(
            running: activities.filter { executionStatus(for: $0) == .running }.count,
            succeeded: activities.filter { $0.status == .completed }.count,
            failed: activities.filter { $0.status == .failed }.count
        )
    }

    static func entryAnimationSignature(for activities: [CodexToolActivity]) -> String {
        activities.map { "\($0.id):\($0.status)" }.joined(separator: "|")
    }

    static func executionStatus(for activity: CodexToolActivity) -> ToolCallExecutionStatus {
        CodexToolActivityStatusSupport.executionStatus(for: activity.status)
    }
}
