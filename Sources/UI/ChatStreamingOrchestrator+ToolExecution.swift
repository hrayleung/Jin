import Foundation

extension ChatStreamingOrchestrator {
    static func executeToolCalls(
        _ executableToolCalls: [ToolCall],
        context ctx: SessionContext,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState,
        callbacks: SessionCallbacks,
        approvalStore: AgentApprovalSessionStore,
        builtinRoutes: BuiltinToolRouteSnapshot,
        agentRoutes: AgentToolRouteSnapshot,
        mcpRoutes: ToolRouteSnapshot
    ) async -> ToolExecutionResult {
        var progress = ToolExecutionProgress()

        for call in executableToolCalls {
            let callStart = Date()
            let route = toolExecutionRoute(
                for: call,
                builtinRoutes: builtinRoutes,
                agentRoutes: agentRoutes
            )
            let isAgentTool = route == .agent

            // Track agent tool activity (running state)
            if isAgentTool {
                let runningActivity = runningAgentToolActivity(for: call)
                await applyAgentToolActivity(
                    runningActivity,
                    accumulator: &accumulator,
                    streamingState: streamingState
                )
            }

            do {
                let result: MCPToolCallResult
                switch route {
                case .agent:
                    let agentControls = ctx.controlsToUse.agentMode ?? AgentModeControls()
                    let approvalDecision = try await agentToolApprovalDecision(
                        for: call,
                        controls: agentControls,
                        approvalStore: approvalStore,
                        callbacks: callbacks,
                        threadID: ctx.threadID
                    )

                    switch approvalDecision {
                    case .approved(let preparation):
                        result = try await AgentToolHub.shared.executeTool(
                            functionName: call.name,
                            arguments: call.arguments,
                            routes: agentRoutes,
                            controls: preparation.controls,
                            preparedShellExecution: preparation.preparedShellExecution
                        )
                    case .denied:
                        let denied = deniedAgentToolExecution(
                            for: call,
                            durationSeconds: Date().timeIntervalSince(callStart)
                        )
                        await applyAgentToolActivity(
                            denied.activity,
                            accumulator: &accumulator,
                            streamingState: streamingState
                        )
                        await applyToolResult(denied.toolResult, streamingState: streamingState)
                        progress.appendResult(denied.toolResult, outputLine: denied.outputLine)
                        continue
                    case .cancelled:
                        return progress.result(cancelled: true)
                    }
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
