import Foundation

extension ChatStreamingOrchestrator {
    static func executeToolCalls(
        _ executableToolCalls: [ToolCall],
        context ctx: SessionContext,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState,
        callbacks: SessionCallbacks,
        builtinRoutes: BuiltinToolRouteSnapshot,
        mcpRoutes: ToolRouteSnapshot
    ) async -> ToolExecutionResult {
        var progress = ToolExecutionProgress()

        for call in executableToolCalls {
            let callStart = Date()
            let route = toolExecutionRoute(
                for: call,
                builtinRoutes: builtinRoutes
            )

            do {
                let result: MCPToolCallResult
                switch route {
                case .builtin:
                    result = try await BuiltinSearchToolHub.shared.executeTool(
                        functionName: call.name,
                        arguments: call.arguments,
                        routes: builtinRoutes
                    )
                case .mcp:
                    result = try await MCPHub.shared.executeTool(
                        functionName: call.name,
                        arguments: call.arguments,
                        routes: mcpRoutes
                    )
                }
                let record = successfulToolExecutionRecord(
                    for: call,
                    route: route,
                    result: result,
                    durationSeconds: Date().timeIntervalSince(callStart),
                    builtinRoutes: builtinRoutes
                )
                await publishToolExecutionRecord(
                    record,
                    progress: &progress,
                    accumulator: &accumulator,
                    streamingState: streamingState
                )
            } catch {
                let record = failedToolExecutionRecord(
                    for: call,
                    route: route,
                    error: error,
                    durationSeconds: Date().timeIntervalSince(callStart),
                    builtinRoutes: builtinRoutes
                )
                await publishToolExecutionRecord(
                    record,
                    progress: &progress,
                    accumulator: &accumulator,
                    streamingState: streamingState
                )
            }
        }

        return progress.result(cancelled: false)
    }
}
