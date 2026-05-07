import Foundation

enum CodexToolActivityStatusSupport {
    static func executionStatus(for status: CodexToolActivityStatus) -> ToolCallExecutionStatus {
        switch status {
        case .running, .unknown:
            return .running
        case .completed:
            return .success
        case .failed:
            return .error
        }
    }
}
