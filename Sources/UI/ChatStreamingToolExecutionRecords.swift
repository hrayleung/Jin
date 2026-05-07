import Foundation

extension ChatStreamingOrchestrator {
    static func successfulToolExecutionRecord(
        for call: ToolCall,
        route: ToolExecutionRoute,
        result: MCPToolCallResult,
        durationSeconds: Double,
        builtinRoutes: BuiltinToolRouteSnapshot
    ) -> ToolExecutionRecord {
        let toolResult = toolResult(
            for: call,
            result: result,
            durationSeconds: durationSeconds
        )
        return ToolExecutionRecord(
            toolResult: toolResult,
            outputLine: toolOutputLine(
                toolName: call.name,
                content: toolResult.content,
                isError: result.isError
            ),
            agentActivity: route == .agent
                ? completedAgentToolActivity(
                    for: call,
                    result: result,
                    normalizedContent: toolResult.content
                )
                : nil,
            searchActivity: toolSearchActivity(
                route: route,
                call: call,
                toolResultText: result.text,
                isError: result.isError,
                builtinRoutes: builtinRoutes
            )
        )
    }

    static func failedToolExecutionRecord(
        for call: ToolCall,
        route: ToolExecutionRoute,
        error: Error,
        durationSeconds: Double,
        builtinRoutes: BuiltinToolRouteSnapshot
    ) -> ToolExecutionRecord {
        let content = toolExecutionFailureContent(for: call, error: error)
        let toolResult = toolResult(
            for: call,
            content: content,
            isError: true,
            durationSeconds: durationSeconds
        )
        return ToolExecutionRecord(
            toolResult: toolResult,
            outputLine: toolOutputLine(
                toolName: call.name,
                content: content,
                isError: true
            ),
            agentActivity: route == .agent ? failedAgentToolActivity(for: call, content: content) : nil,
            searchActivity: toolSearchActivity(
                route: route,
                call: call,
                toolResultText: content,
                isError: true,
                builtinRoutes: builtinRoutes
            )
        )
    }
}
