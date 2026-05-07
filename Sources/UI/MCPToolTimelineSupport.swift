import Foundation

enum MCPToolTimelineSupport {
    struct Entry: Identifiable {
        let call: ToolCall
        let result: ToolResult?

        var id: String { call.id }

        var status: ToolCallExecutionStatus {
            MCPToolTimelineSupport.status(for: result)
        }
    }

    struct StatusCounts: Equatable {
        let running: Int
        let succeeded: Int
        let failed: Int
    }

    struct CompactStatusBadge: Equatable {
        enum Tone: Equatable {
            case success
            case failure
        }

        let count: Int
        let icon: String
        let tone: Tone
    }

    struct IconStackLayout: Equatable {
        let displayedServerIDs: [String]
        let iconFrameSize: Double
        let overlapOffset: Double
        let totalWidth: Double
    }

    struct ParsedFunctionName: Equatable {
        let serverID: String
        let toolName: String
    }
}
