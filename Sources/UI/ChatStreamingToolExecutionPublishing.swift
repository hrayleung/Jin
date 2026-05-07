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

        if let agentActivity = record.agentActivity {
            await applyAgentToolActivity(
                agentActivity,
                accumulator: &accumulator,
                streamingState: streamingState
            )
        }

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

    static func applyAgentToolActivity(
        _ activity: CodexToolActivity,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState
    ) async {
        accumulator.upsertAgentToolActivity(activity)
        await MainActor.run {
            streamingState.upsertAgentToolActivity(activity)
        }
    }
}
