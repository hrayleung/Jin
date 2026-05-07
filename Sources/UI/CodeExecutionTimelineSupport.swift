import Foundation

enum CodeExecutionTimelineSupport {
    enum CompactStatusKind: Equatable {
        case success
        case failure
    }

    struct CompactStatus: Equatable {
        let text: String
        let icon: String
        let kind: CompactStatusKind
    }

    struct ActivityCounts: Equatable {
        let active: Int
        let completed: Int
        let failed: Int
    }

    static func initialExpansion(
        isStreaming: Bool,
        displayMode: CodeExecutionDisplayMode
    ) -> Bool {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming
        }
        return displayMode.startsExpandedOnComplete
    }

    static func shouldExpandAfterStreamingChange(
        isStreaming: Bool,
        displayMode: CodeExecutionDisplayMode
    ) -> Bool? {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming ? true : nil
        }
        return displayMode == .collapseOnComplete ? false : nil
    }

    static func hasActiveExecution(_ activities: [CodeExecutionActivity]) -> Bool {
        counts(for: activities).active > 0
    }

    static func counts(for activities: [CodeExecutionActivity]) -> ActivityCounts {
        var active = 0
        var completed = 0
        var failed = 0

        for activity in activities {
            switch countBucket(for: activity.status) {
            case .active:
                active += 1
            case .completed:
                completed += 1
            case .failed:
                failed += 1
            case .ignored:
                break
            }
        }

        return ActivityCounts(active: active, completed: completed, failed: failed)
    }

    static func headerTitle(activityCount: Int) -> String {
        if activityCount == 1 {
            return "Code Execution"
        }
        return "\(activityCount) Code Executions"
    }

    static func compactStatus(for activities: [CodeExecutionActivity]) -> CompactStatus? {
        let counts = counts(for: activities)
        if counts.active > 0 {
            return nil
        }

        if counts.failed > 0 {
            return CompactStatus(
                text: failureLabel(completedCount: counts.completed, failedCount: counts.failed),
                icon: "xmark.circle",
                kind: .failure
            )
        }

        if counts.completed > 0 {
            return CompactStatus(
                text: "Done",
                icon: "checkmark.circle",
                kind: .success
            )
        }
        return nil
    }

    static func animationSignature(for activities: [CodeExecutionActivity]) -> String {
        activities
            .map { "\($0.id):\($0.status)" }
            .joined(separator: "|")
    }

    private enum CountBucket {
        case active
        case completed
        case failed
        case ignored
    }

    private static func countBucket(for status: CodeExecutionStatus) -> CountBucket {
        switch status {
        case .inProgress, .writingCode, .interpreting:
            return .active
        case .completed:
            return .completed
        case .failed, .incomplete:
            return .failed
        case .unknown:
            return .ignored
        }
    }

    private static func failureLabel(completedCount: Int, failedCount: Int) -> String {
        if completedCount > 0 {
            return "\(completedCount) ok / \(failedCount) failed"
        }
        return failedCount == 1 ? "Failed" : "\(failedCount) failed"
    }
}
