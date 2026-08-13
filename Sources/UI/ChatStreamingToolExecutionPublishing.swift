import Foundation

extension ChatStreamingOrchestrator {
    static func publishToolExecutionRecord(
        _ record: ToolExecutionRecord,
        progress: inout ToolExecutionProgress,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState,
        callbacks: SessionCallbacks
    ) async {
        await applyToolResult(record.toolResult, streamingState: streamingState)
        progress.appendResult(record.toolResult, outputLine: record.outputLine)

        await MainActor.run {
            callbacks.upsertLiveToolResult(record.toolResult)
        }

        if let searchActivity = record.searchActivity {
            progress.upsertSearchActivity(searchActivity)
            // The activity is merged into the round-1 persisted message via
            // mergeSearchActivities in persistToolContinuation. Writing it here
            // into streamingState — which after reset represents the next round's
            // bubble — would briefly show the card at the bottom of the chat and
            // then "jump" to the top after merge.
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
