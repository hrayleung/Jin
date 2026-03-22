import Collections
import Foundation

extension ChatStreamingOrchestrator {

    struct ToolExecutionResult {
        let results: [ToolResult]
        let outputLines: [String]
        let searchActivities: [SearchActivity]
        let cancelled: Bool
    }

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
        var toolResults: [ToolResult] = []
        var toolOutputLines: [String] = []
        var toolSearchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]

        func upsertToolSearchActivity(_ activity: SearchActivity) {
            if let existing = toolSearchActivitiesByID[activity.id] {
                toolSearchActivitiesByID[activity.id] = existing.merged(with: activity)
            } else {
                toolSearchActivitiesByID[activity.id] = activity
            }
        }

        for call in executableToolCalls {
            let callStart = Date()
            let isAgentTool = agentRoutes.contains(functionName: call.name)

            // Track agent tool activity (running state)
            if isAgentTool {
                let runningActivity = CodexToolActivity(
                    id: call.id,
                    toolName: call.name,
                    status: .running,
                    arguments: call.arguments
                )
                accumulator.upsertAgentToolActivity(runningActivity)
                await MainActor.run {
                    streamingState.upsertAgentToolActivity(runningActivity)
                }
            }

            do {
                let result: MCPToolCallResult
                if isAgentTool {
                    // Agent tool: check approval for shell commands and file writes
                    let agentControls = ctx.controlsToUse.agentMode ?? AgentModeControls()
                    let preparedShellExecution: AgentToolHub.PreparedShellExecution?
                    if call.name == AgentToolHub.shellExecuteFunctionName {
                        preparedShellExecution = try await AgentToolHub.shared.prepareShellExecution(
                            arguments: call.arguments,
                            controls: agentControls
                        )
                    } else {
                        preparedShellExecution = nil
                    }
                    // Approvals are keyed on the user's original tool intent, not RTK's
                    // internal rewrite. executeShell() separately validates that the rewritten
                    // command is an RTK command before running it.
                    let approvalKey = agentApprovalSessionKey(
                        functionName: call.name,
                        arguments: call.arguments,
                        controls: agentControls
                    )
                    let needsApproval = await agentToolNeedsApproval(
                        functionName: call.name,
                        arguments: call.arguments,
                        controls: agentControls,
                        approvalKey: approvalKey,
                        approvalStore: approvalStore
                    )

                    if needsApproval {
                        let approvalRequest = makeAgentApprovalRequest(
                            functionName: call.name,
                            arguments: call.arguments,
                            controls: agentControls
                        )
                        await MainActor.run {
                            callbacks.appendAgentApproval(approvalRequest, ctx.threadID)
                        }
                        let choice = await approvalRequest.waitForResponse()
                        switch choice {
                        case .deny:
                            let deniedActivity = CodexToolActivity(
                                id: call.id,
                                toolName: call.name,
                                status: .failed,
                                arguments: call.arguments,
                                output: "Denied by user"
                            )
                            accumulator.upsertAgentToolActivity(deniedActivity)
                            await MainActor.run {
                                streamingState.upsertAgentToolActivity(deniedActivity)
                            }
                            let toolResult = ToolResult(
                                toolCallID: call.id,
                                toolName: call.name,
                                content: "User denied this tool call. Do not retry this exact action without permission.",
                                isError: true,
                                signature: call.signature,
                                durationSeconds: Date().timeIntervalSince(callStart)
                            )
                            toolResults.append(toolResult)
                            await MainActor.run {
                                streamingState.upsertToolResult(toolResult)
                            }
                            toolOutputLines.append("Tool \(call.name) denied by user.")
                            continue
                        case .cancel:
                            return ToolExecutionResult(
                                results: toolResults,
                                outputLines: toolOutputLines,
                                searchActivities: Array(toolSearchActivitiesByID.values),
                                cancelled: true
                            )
                        case .allow, .allowForSession:
                            if choice == .allowForSession, let approvalKey {
                                await approvalStore.approve(key: approvalKey)
                            }
                            break
                        }
                    }

                    result = try await AgentToolHub.shared.executeTool(
                        functionName: call.name,
                        arguments: call.arguments,
                        routes: agentRoutes,
                        controls: agentControls,
                        preparedShellExecution: preparedShellExecution
                    )
                } else if builtinRoutes.contains(functionName: call.name) {
                    result = try await BuiltinSearchToolHub.shared.executeTool(
                        functionName: call.name,
                        arguments: call.arguments,
                        routes: builtinRoutes
                    )
                } else {
                    result = try await MCPHub.shared.executeTool(
                        functionName: call.name,
                        arguments: call.arguments,
                        routes: mcpRoutes
                    )
                }
                let duration = Date().timeIntervalSince(callStart)
                let normalizedContent = ToolSearchActivityFactory.normalizedToolResultContent(
                    result.text,
                    toolName: call.name,
                    isError: result.isError
                )
                let toolResult = ToolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: normalizedContent,
                    isError: result.isError,
                    signature: call.signature,
                    durationSeconds: duration,
                    rawOutputPath: result.rawOutputPath
                )
                toolResults.append(toolResult)
                await MainActor.run {
                    streamingState.upsertToolResult(toolResult)
                }

                if result.isError {
                    toolOutputLines.append("Tool \(call.name) failed:\n\(normalizedContent)")
                } else {
                    toolOutputLines.append("Tool \(call.name):\n\(normalizedContent)")
                }

                // Track agent tool completion
                if isAgentTool {
                    let completedActivity = CodexToolActivity(
                        id: call.id,
                        toolName: call.name,
                        status: result.isError ? .failed : .completed,
                        arguments: call.arguments,
                        output: String(normalizedContent.prefix(4096)),
                        rawOutputPath: result.rawOutputPath
                    )
                    accumulator.upsertAgentToolActivity(completedActivity)
                    await MainActor.run {
                        streamingState.upsertAgentToolActivity(completedActivity)
                    }
                }

                if builtinRoutes.contains(functionName: call.name),
                   let activity = ToolSearchActivityFactory.activityFromToolResult(
                    call: call,
                    toolResultText: result.text,
                    isError: result.isError,
                    providerOverride: builtinRoutes.provider(for: call.name)
                ) {
                    upsertToolSearchActivity(activity)
                    await MainActor.run {
                        streamingState.upsertSearchActivity(activity)
                    }
                }
            } catch {
                let duration = Date().timeIntervalSince(callStart)
                let normalizedError = ToolSearchActivityFactory.normalizedToolResultContent(
                    error.localizedDescription,
                    toolName: call.name,
                    isError: true
                )
                let llmErrorContent = "Tool execution failed: \(normalizedError). You may retry this tool call with corrected arguments."
                let toolResult = ToolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: llmErrorContent,
                    isError: true,
                    signature: call.signature,
                    durationSeconds: duration,
                    rawOutputPath: nil
                )
                toolResults.append(toolResult)
                await MainActor.run {
                    streamingState.upsertToolResult(toolResult)
                }
                toolOutputLines.append("Tool \(call.name) failed:\n\(llmErrorContent)")

                // Track agent tool failure
                if isAgentTool {
                    let failedActivity = CodexToolActivity(
                        id: call.id,
                        toolName: call.name,
                        status: .failed,
                        arguments: call.arguments,
                        output: String(llmErrorContent.prefix(4096)),
                        rawOutputPath: nil
                    )
                    accumulator.upsertAgentToolActivity(failedActivity)
                    await MainActor.run {
                        streamingState.upsertAgentToolActivity(failedActivity)
                    }
                }

                if builtinRoutes.contains(functionName: call.name),
                   let activity = ToolSearchActivityFactory.activityFromToolResult(
                    call: call,
                    toolResultText: llmErrorContent,
                    isError: true,
                    providerOverride: builtinRoutes.provider(for: call.name)
                ) {
                    upsertToolSearchActivity(activity)
                    await MainActor.run {
                        streamingState.upsertSearchActivity(activity)
                    }
                }
            }
        }

        return ToolExecutionResult(
            results: toolResults,
            outputLines: toolOutputLines,
            searchActivities: Array(toolSearchActivitiesByID.values),
            cancelled: false
        )
    }
}
