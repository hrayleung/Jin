import Foundation

extension ChatStreamingOrchestrator {
    static func publishToolExecutionRecord(
        _ record: ToolExecutionRecord,
        progress: inout ToolExecutionProgress,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState
    ) async {
        await applyToolResult(record.toolResult, streamingState: streamingState)
        progress.appendResult(record.toolResult, outputLine: record.outputLine)

        if let searchActivity = record.searchActivity {
            progress.upsertSearchActivity(searchActivity)
            await MainActor.run {
                streamingState.upsertSearchActivity(searchActivity)
            }
        }
    }

    static func applyToolResult(
        _ result: ToolResult,
        streamingState: StreamingMessageState
    ) async {
        await MainActor.run {
            streamingState.upsertToolResult(result)
        }
    }
}
