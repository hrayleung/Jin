import Foundation

enum ChatToolResultIndexBuilder {
    static func toolResultsByToolCallID(in messageEntities: [MessageEntity]) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        let decoder = JSONDecoder()
        for entity in messageEntities where entity.role == MessageRole.tool.rawValue {
            guard let data = entity.toolResultsData,
                  let toolResults = try? decoder.decode([ToolResult].self, from: data) else {
                continue
            }
            merge(toolResults, into: &results)
        }

        return results
    }

    static func toolResultsByToolCallID(in messageSnapshots: [PersistedMessageSnapshot]) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        let decoder = JSONDecoder()
        for snapshot in messageSnapshots where snapshot.role == MessageRole.tool.rawValue {
            if Task.isCancelled { break }
            guard let data = snapshot.toolResultsData,
                  let toolResults = try? decoder.decode([ToolResult].self, from: data) else {
                continue
            }
            merge(toolResults, into: &results)
        }

        return results
    }

    private static func merge(_ toolResults: [ToolResult], into results: inout [String: ToolResult]) {
        for result in toolResults {
            results[result.toolCallID] = result
        }
    }
}
