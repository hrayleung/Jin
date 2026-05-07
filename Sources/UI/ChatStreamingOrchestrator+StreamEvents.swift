import Foundation

extension ChatStreamingOrchestrator {
    static func handleStreamEvent(
        _ event: StreamEvent,
        state: inout StreamEventHandlingState,
        requestControls: inout GenerationControls,
        streamingState: StreamingMessageState,
        builtinRoutes: BuiltinToolRouteSnapshot,
        context ctx: SessionContext,
        callbacks: SessionCallbacks
    ) async throws {
        switch event {
        case .messageStart:
            break
        case .contentDelta(let part):
            applyStreamContentPart(
                part,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer,
                diagnostics: &state.diagnostics,
                context: ctx
            )
        case .thinkingDelta(let delta):
            applyStreamThinkingDelta(
                delta,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer,
                diagnostics: &state.diagnostics,
                context: ctx
            )
        case .toolCallStart(let call):
            if let searchActivity = toolSearchStartActivity(
                for: call,
                builtinRoutes: builtinRoutes
            ) {
                await applyStreamSearchActivity(
                    searchActivity,
                    accumulator: &state.accumulator,
                    streamingState: streamingState
                )
            }
            await applyStreamToolCall(
                call,
                accumulator: &state.accumulator,
                streamingState: streamingState
            )
        case .toolCallDelta:
            break
        case .toolCallEnd(let call):
            await applyStreamToolCall(
                call,
                accumulator: &state.accumulator,
                streamingState: streamingState
            )
        case .searchActivity(let activity):
            await applyStreamSearchActivity(
                activity,
                accumulator: &state.accumulator,
                streamingState: streamingState
            )
        case .codeExecutionActivity(let activity):
            await applyStreamCodeExecutionActivity(
                activity,
                accumulator: &state.accumulator,
                streamingState: streamingState
            )
        case .codexToolActivity(let activity):
            await applyStreamCodexToolActivity(
                activity,
                accumulator: &state.accumulator,
                streamingState: streamingState
            )
        case .codexInteractionRequest(let request):
            await flushStreamingUIIfNeeded(
                buffer: &state.uiFlushBuffer,
                force: true,
                now: ProcessInfo.processInfo.systemUptime,
                streamingState: streamingState,
                context: ctx
            )
            await MainActor.run {
                callbacks.appendCodexInteraction(request, ctx.threadID)
            }
        case .codexThreadState(let threadState):
            await applyRequestControlStreamUpdate(
                .codexThread(threadState),
                requestControls: &requestControls,
                threadID: ctx.threadID,
                callbacks: callbacks
            )
        case .claudeManagedSessionState(let sessionState):
            await applyRequestControlStreamUpdate(
                .claudeManagedSession(sessionState),
                requestControls: &requestControls,
                threadID: ctx.threadID,
                callbacks: callbacks
            )
        case .claudeManagedCustomToolResults(let results):
            await applyRequestControlStreamUpdate(
                .claudeManagedCustomToolResults(results),
                requestControls: &requestControls,
                threadID: ctx.threadID,
                callbacks: callbacks
            )
        case .messageEnd:
            await MainActor.run {
                streamingState.markThinkingComplete()
            }
        case .error(let err):
            throw err
        }

        await flushStreamingUIIfNeeded(
            buffer: &state.uiFlushBuffer,
            now: ProcessInfo.processInfo.systemUptime,
            streamingState: streamingState,
            context: ctx
        )
    }
}
