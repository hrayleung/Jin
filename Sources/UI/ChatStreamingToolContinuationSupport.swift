import Foundation

extension ChatStreamingOrchestrator {
    struct ToolContinuationPersistenceResult {
        let toolMessage: Message
        let claudeManagedToolResultsForNextRequest: [ClaudeManagedAgentPendingToolResult]
    }

    static func claudeManagedPendingToolResults(
        for toolCalls: [ToolCall],
        toolResults: [ToolResult]
    ) -> [ClaudeManagedAgentPendingToolResult] {
        let resultsByToolCallID = toolResults.reduce(into: [String: ToolResult]()) { partialResult, result in
            partialResult[result.toolCallID] = partialResult[result.toolCallID] ?? result
        }

        return toolCalls.compactMap { call -> ClaudeManagedAgentPendingToolResult? in
            guard let result = resultsByToolCallID[call.id] else { return nil }
            return claudeManagedPendingToolResult(for: call, result: result)
        }
    }

    static func claudeManagedPendingToolResult(
        for call: ToolCall,
        result: ToolResult
    ) -> ClaudeManagedAgentPendingToolResult {
        ClaudeManagedAgentPendingToolResult(
            eventID: call.id,
            toolCallID: call.providerContextValue(for: ClaudeManagedAgentProviderContextKey.underlyingToolUseID) ?? call.id,
            toolName: result.toolName ?? call.name,
            content: result.content,
            isError: result.isError,
            sessionThreadID: call.providerContextValue(for: ClaudeManagedAgentProviderContextKey.sessionThreadID)
        )
    }

    static func followUpToolMessage(from result: ToolExecutionResult) -> Message {
        Message(
            role: .tool,
            content: result.outputLines.isEmpty ? [] : [.text(result.outputLines.joined(separator: "\n\n"))],
            toolResults: result.results,
            searchActivities: result.searchActivities.isEmpty ? nil : result.searchActivities
        )
    }

    static func persistToolContinuation(
        executableToolCalls: [ToolCall],
        toolExecutionResult: ToolExecutionResult,
        persistedAssistantMessageID: UUID?,
        providerType: ProviderType,
        context ctx: SessionContext,
        callbacks: SessionCallbacks
    ) async -> ToolContinuationPersistenceResult {
        let claudeManagedToolResultsForNextRequest: [ClaudeManagedAgentPendingToolResult]

        if providerType == .claudeManagedAgents, !toolExecutionResult.results.isEmpty {
            let pendingResults = claudeManagedPendingToolResults(
                for: executableToolCalls,
                toolResults: toolExecutionResult.results
            )
            claudeManagedToolResultsForNextRequest = pendingResults
            await MainActor.run {
                callbacks.persistClaudeManagedPendingToolResults(pendingResults, ctx.threadID)
            }
        } else {
            claudeManagedToolResultsForNextRequest = []
        }

        if let assistantMessageID = persistedAssistantMessageID, !toolExecutionResult.searchActivities.isEmpty {
            await MainActor.run {
                callbacks.mergeSearchActivities(assistantMessageID, toolExecutionResult.searchActivities)
            }
        }

        let toolMessage = followUpToolMessage(from: toolExecutionResult)
        await MainActor.run {
            callbacks.persistToolMessage(toolMessage, ctx.threadID, ctx.turnID)
        }

        return ToolContinuationPersistenceResult(
            toolMessage: toolMessage,
            claudeManagedToolResultsForNextRequest: claudeManagedToolResultsForNextRequest
        )
    }

    static func applyToolContinuationFollowUp(
        _ result: ToolContinuationPersistenceResult,
        providerType: ProviderType,
        requestControls: inout GenerationControls,
        history: [Message]
    ) -> [Message] {
        if providerType == .claudeManagedAgents {
            requestControls.applyChatStreamingUpdate(
                .claudeManagedCustomToolResults(result.claudeManagedToolResultsForNextRequest)
            )
        }

        var updatedHistory = history
        updatedHistory.append(result.toolMessage)
        return updatedHistory
    }
}
