import Foundation
import Collections

extension ChatStreamingOrchestrator {
    struct ToolExecutionProgress {
        private(set) var results: [ToolResult] = []
        private(set) var outputLines: [String] = []
        private var searchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]

        var searchActivities: [SearchActivity] {
            Array(searchActivitiesByID.values)
        }

        mutating func appendResult(_ result: ToolResult, outputLine: String) {
            results.append(result)
            outputLines.append(outputLine)
        }

        mutating func upsertSearchActivity(_ activity: SearchActivity) {
            if let existing = searchActivitiesByID[activity.id] {
                searchActivitiesByID[activity.id] = existing.merged(with: activity)
            } else {
                searchActivitiesByID[activity.id] = activity
            }
        }

        func result(cancelled: Bool) -> ToolExecutionResult {
            ToolExecutionResult(
                results: results,
                outputLines: outputLines,
                searchActivities: searchActivities,
                cancelled: cancelled
            )
        }
    }

    struct ToolExecutionResult {
        let results: [ToolResult]
        let outputLines: [String]
        let searchActivities: [SearchActivity]
        let cancelled: Bool
    }

    struct ToolExecutionRecord {
        let toolResult: ToolResult
        let outputLine: String
        let searchActivity: SearchActivity?
    }

    enum ToolExecutionRoute: Equatable {
        case builtin
        case mcp
    }
}
