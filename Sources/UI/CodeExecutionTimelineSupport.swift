import Foundation

enum CodeExecutionTimelineSupport {
    struct HeaderStatus: Equatable {
        enum Kind: Equatable {
            case running
            case success
            case failure
        }

        let kind: Kind
        let text: String?
        let icon: String?
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

    static func isSingleExecution(_ activities: [CodeExecutionActivity]) -> Bool {
        activities.count == 1
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

    static func headerStatus(for activities: [CodeExecutionActivity]) -> HeaderStatus? {
        let counts = counts(for: activities)
        if counts.active > 0 {
            return HeaderStatus(
                kind: .running,
                text: runningLabel(for: activities),
                icon: nil
            )
        }

        if counts.failed > 0 {
            return HeaderStatus(
                kind: .failure,
                text: failureLabel(completedCount: counts.completed, failedCount: counts.failed),
                icon: "xmark.circle.fill"
            )
        }

        if counts.completed > 0 {
            return HeaderStatus(
                kind: .success,
                text: nil,
                icon: "checkmark.circle.fill"
            )
        }
        return nil
    }

    /// One-line collapsed preview for the common single-execution path.
    static func collapsedPreview(for activities: [CodeExecutionActivity]) -> String? {
        guard let activity = activities.first, activities.count == 1 else { return nil }
        if let line = firstNonEmptyLine(activity.code) {
            return line
        }
        switch activity.status {
        case .writingCode:
            return "Writing code..."
        case .interpreting:
            return "Running code..."
        case .inProgress:
            return "Starting..."
        case .completed, .failed, .incomplete, .unknown:
            return nil
        }
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

    private static func runningLabel(for activities: [CodeExecutionActivity]) -> String {
        var sawWriting = false
        for activity in activities {
            switch activity.status {
            case .interpreting:
                return "Running"
            case .writingCode:
                sawWriting = true
            default:
                break
            }
        }
        return sawWriting ? "Writing" : "Starting"
    }

    private static func failureLabel(completedCount: Int, failedCount: Int) -> String {
        if completedCount > 0 {
            return "\(completedCount) ok / \(failedCount) failed"
        }
        return failedCount == 1 ? "Failed" : "\(failedCount) failed"
    }

    private static func firstNonEmptyLine(_ text: String?) -> String? {
        guard let text else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let trimmed = String(line).trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
    }
}
