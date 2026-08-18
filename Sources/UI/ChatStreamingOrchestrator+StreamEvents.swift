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
                applyStreamSearchActivity(
                    searchActivity,
                    accumulator: &state.accumulator,
                    uiFlushBuffer: &state.uiFlushBuffer
                )
            }
            applyStreamToolCall(
                call,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer
            )
        case .toolCallDelta:
            break
        case .toolCallEnd(let call):
            if let searchActivity = toolSearchStartActivity(
                for: call,
                builtinRoutes: builtinRoutes
            ) {
                applyStreamSearchActivity(
                    searchActivity,
                    accumulator: &state.accumulator,
                    uiFlushBuffer: &state.uiFlushBuffer
                )
            }
            applyStreamToolCall(
                call,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer
            )
        case .searchActivity(let activity):
            applyStreamSearchActivity(
                activity,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer
            )
        case .codeExecutionActivity(let activity):
            applyStreamCodeExecutionActivity(
                activity,
                accumulator: &state.accumulator,
                uiFlushBuffer: &state.uiFlushBuffer
            )
        case .managedAgentInteractionRequest(let request):
            await flushStreamingUIIfNeeded(
                buffer: &state.uiFlushBuffer,
                force: true,
                now: ProcessInfo.processInfo.systemUptime,
                streamingState: streamingState,
                context: ctx
            )
            await MainActor.run {
                callbacks.appendManagedAgentInteraction(request)
            }
        case .claudeManagedSessionState(let sessionState):
            await applyRequestControlStreamUpdate(
                .claudeManagedSession(sessionState),
                requestControls: &requestControls,
                callbacks: callbacks
            )
        case .claudeManagedCustomToolResults(let results):
            await applyRequestControlStreamUpdate(
                .claudeManagedCustomToolResults(results),
                requestControls: &requestControls,
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
