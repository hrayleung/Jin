import Foundation

enum CodexToolTimelineSupport {
    struct Entry: Identifiable {
        let activity: CodexToolActivity

        var id: String { activity.id }

        var executionStatus: ToolCallExecutionStatus {
            CodexToolTimelineSupport.executionStatus(for: activity)
        }
    }

    struct ActivityCounts: Equatable {
        let running: Int
        let succeeded: Int
        let failed: Int
    }

    struct CompactStatus: Equatable {
        enum Tone: Equatable {
            case success
            case failure
        }

        let text: String
        let icon: String
        let tone: Tone
    }
}
