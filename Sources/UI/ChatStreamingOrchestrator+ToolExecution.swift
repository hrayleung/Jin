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
        var cancelled = false

        for call in executableToolCalls {
            if Task.isCancelled {
                cancelled = true
                break
            }
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

                // The tool may have completed after the user pressed Stop: nothing in
                // the MCP call path cooperates with cancellation yet, so a late success
                // would otherwise be published and the turn allowed to continue.
                if Task.isCancelled {
                    cancelled = true
                    break
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
            } catch is CancellationError {
                // The user stopped the turn; recording this as a tool failure would be
                // wrong, and recording it as a success is what this used to do.
                cancelled = true
                break
            } catch {
                if Task.isCancelled {
                    cancelled = true
                    break
                }
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

        return progress.result(cancelled: cancelled)
    }
}
