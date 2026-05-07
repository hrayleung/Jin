import Foundation

enum AgentToolTimelineSupport {
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
