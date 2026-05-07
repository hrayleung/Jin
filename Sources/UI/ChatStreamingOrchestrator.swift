import Foundation

/// Encapsulates the streaming response loop that was previously inline in ChatView's
/// `startStreamingResponse`. All mutable ChatView state is accessed through typed callbacks
/// so the orchestrator remains decoupled from the view layer.
enum ChatStreamingOrchestrator {
    @Sendable
    static func run(
        context ctx: SessionContext,
        streamingState: StreamingMessageState,
        callbacks: SessionCallbacks
    ) async {
        await NetworkDebugLogScope.$current.withValue(ctx.networkLogContext) {
            var completionNotification = CompletionNotificationState()
            let approvalStore = AgentApprovalSessionStore()

            do {
                let preparedSession = try await prepareSession(from: ctx)
                let providerConfig = preparedSession.providerConfig
                let adapter = preparedSession.adapter
                let allTools = preparedSession.allTools
                let mcpRoutes = preparedSession.mcpRoutes
                let builtinRoutes = preparedSession.builtinRoutes
                let agentRoutes = preparedSession.agentRoutes
                var history = preparedSession.history
                var requestControls = preparedSession.requestControls
                var iteration = 0

                while iteration < preparedSession.maxToolIterations {
                    try Task.checkCancellation()

                    var eventState = StreamEventHandlingState(providerType: providerConfig.type)
                    var metricsCollector = StreamingResponseMetricsCollector()
                    metricsCollector.begin(at: Date())

                    await MainActor.run {
                        streamingState.reset()
                    }

                    let streamCreationStartedAt = ProcessInfo.processInfo.systemUptime
                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: ctx.modelID,
                        controls: requestControls,
                        tools: allTools,
                        streaming: ctx.resolvedModelSettings?.capabilities.contains(.streaming) ?? true
                    )
                    let streamCreationDurationMs = Int((ProcessInfo.processInfo.systemUptime - streamCreationStartedAt) * 1000)

                    logAdapterStreamCreated(
                        providerType: providerConfig.type,
                        modelID: ctx.modelID,
                        historyCount: history.count,
                        toolCount: allTools.count,
                        durationMs: streamCreationDurationMs,
                        context: ctx
                    )

                    for try await event in stream {
                        try Task.checkCancellation()
                        observeStreamEvent(
                            event,
                            at: Date(),
                            metricsCollector: &metricsCollector,
                            diagnostics: &eventState.diagnostics,
                            context: ctx
                        )

                        try await handleStreamEvent(
                            event,
                            state: &eventState,
                            requestControls: &requestControls,
                            streamingState: streamingState,
                            builtinRoutes: builtinRoutes,
                            context: ctx,
                            callbacks: callbacks
                        )
                    }

                    await flushStreamingUIIfNeeded(
                        buffer: &eventState.uiFlushBuffer,
                        force: true,
                        now: ProcessInfo.processInfo.systemUptime,
                        streamingState: streamingState,
                        context: ctx
                    )
                    metricsCollector.end(at: Date())

                    let responseSnapshot = eventState.accumulator.snapshot()
                    let responseMetrics = metricsCollector.metrics
                    let persistenceResult = await persistAssistantOutput(
                        response: responseSnapshot,
                        responseMetrics: responseMetrics,
                        context: ctx,
                        callbacks: callbacks
                    )

                    completionNotification.observe(persistenceResult)
                    let persistedAssistantMessageID = persistenceResult.persistedMessageID
                    let hasRenderableAssistantContent = persistenceResult.hasRenderableContent
                    history = await applyAssistantPersistenceFollowUp(
                        persistenceResult,
                        responseHasToolCalls: !responseSnapshot.toolCalls.isEmpty,
                        history: history,
                        context: ctx,
                        callbacks: callbacks
                    )

                    let executableToolCalls = executableToolCalls(from: responseSnapshot.toolCalls)

                    guard !executableToolCalls.isEmpty else {
                        completionNotification.finishWithoutToolContinuation(
                            hasRenderableContent: hasRenderableAssistantContent
                        )
                        break
                    }

                    await MainActor.run {
                        streamingState.reset()
                        streamingState.setToolCalls(executableToolCalls)
                    }

                    let toolExecutionResult = await executeToolCalls(
                        executableToolCalls,
                        context: ctx,
                        accumulator: &eventState.accumulator,
                        streamingState: streamingState,
                        callbacks: callbacks,
                        approvalStore: approvalStore,
                        builtinRoutes: builtinRoutes,
                        agentRoutes: agentRoutes,
                        mcpRoutes: mcpRoutes
                    )

                    guard !toolExecutionResult.cancelled else { return }

                    let completedAgentActivities = eventState.accumulator.buildAgentToolActivities()
                    let continuationPersistenceResult = await persistToolContinuation(
                        executableToolCalls: executableToolCalls,
                        toolExecutionResult: toolExecutionResult,
                        completedAgentActivities: completedAgentActivities,
                        persistedAssistantMessageID: persistedAssistantMessageID,
                        providerType: providerConfig.type,
                        context: ctx,
                        callbacks: callbacks
                    )
                    history = applyToolContinuationFollowUp(
                        continuationPersistenceResult,
                        providerType: providerConfig.type,
                        requestControls: &requestControls,
                        history: history
                    )
                    iteration += 1
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    callbacks.showError(error.localizedDescription)
                }
            }
            let shouldNotifyNow = completionNotification.shouldNotify
            let previewForNotification = completionNotification.preview
            await MainActor.run {
                callbacks.onSessionEnd(shouldNotifyNow, previewForNotification, ctx.threadID)
            }
        }
    }

}
