import Collections
import CryptoKit
import Foundation

/// Encapsulates the streaming response loop that was previously inline in ChatView's
/// `startStreamingResponse`. All mutable ChatView state is accessed through typed callbacks
/// so the orchestrator remains decoupled from the view layer.
enum ChatStreamingOrchestrator {

    struct SessionContext: Sendable {
        let conversationID: UUID
        let threadID: UUID
        let turnID: UUID?
        let providerID: String
        let providerConfig: ProviderConfig?
        let providerType: ProviderType?
        let modelID: String
        let modelNameSnapshot: String
        let resolvedModelSettings: ResolvedModelSettings?
        let messageSnapshots: [PersistedMessageSnapshot]
        let systemPrompt: String?
        let controlsToUse: GenerationControls
        let shouldTruncateMessages: Bool
        let maxHistoryMessages: Int?
        let modelContextWindow: Int
        let reservedOutputTokens: Int
        let mcpServerConfigs: [MCPServerConfig]
        let chatNamingTarget: (provider: ProviderConfig, modelID: String)?
        let shouldOfferBuiltinSearch: Bool
        let triggeredByUserSend: Bool
        let networkLogContext: NetworkDebugLogContext
    }

    struct SessionCallbacks {
        /// Persist an assistant message entity; returns the entity's UUID on success.
        let persistAssistantMessage: @MainActor (
            _ message: Message,
            _ providerID: String,
            _ modelID: String,
            _ modelName: String,
            _ threadID: UUID,
            _ turnID: UUID?,
            _ metrics: ResponseMetrics?
        ) -> UUID?

        /// Persist a tool-result message entity.
        let persistToolMessage: @MainActor (
            _ message: Message,
            _ threadID: UUID,
            _ turnID: UUID?
        ) -> Void

        /// Save Codex remote thread state for a local thread.
        let persistCodexThreadState: @MainActor (CodexThreadState, _ localThreadID: UUID) -> Void

        /// Save Claude Managed Agents remote session state for a local thread.
        let persistClaudeManagedSessionState: @MainActor (ClaudeManagedAgentSessionState, _ localThreadID: UUID) -> Void

        /// Save pending Claude Managed Agents custom tool results for the next turn.
        let persistClaudeManagedPendingToolResults: @MainActor (_ results: [ClaudeManagedAgentPendingToolResult], _ localThreadID: UUID) -> Void

        /// Queue a Codex interaction request for the user.
        let appendCodexInteraction: @MainActor (CodexInteractionRequest, _ localThreadID: UUID) -> Void

        /// Merge search activities into a previously persisted assistant message.
        let mergeSearchActivities: @MainActor (_ messageID: UUID, _ activities: [SearchActivity]) -> Void

        /// Merge agent tool activities into a previously persisted assistant message.
        let mergeAgentToolActivities: @MainActor (_ messageID: UUID, _ activities: [CodexToolActivity]) -> Void

        /// Optionally auto-rename the conversation after the first assistant reply.
        let maybeAutoRename: @MainActor (
            _ provider: ProviderConfig,
            _ modelID: String,
            _ history: [Message],
            _ assistantMessage: Message
        ) async -> Void

        /// Queue an agent approval request for the user.
        let appendAgentApproval: @MainActor (AgentApprovalRequest, _ localThreadID: UUID) -> Void

        /// Display an error to the user.
        let showError: @MainActor (String) -> Void

        /// End the streaming session (called when tool calls are empty after persisting assistant message).
        let endStreamingSession: @MainActor () -> Void

        /// Final cleanup: notify completion, end session, and clean up codex interactions.
        let onSessionEnd: @MainActor (_ shouldNotify: Bool, _ preview: String?, _ threadID: UUID) -> Void
    }

    static func hasRenderableAssistantContent(
        assistantPartCount: Int,
        searchActivityCount: Int,
        codeExecutionActivityCount: Int,
        codexToolActivityCount: Int,
        agentToolActivityCount: Int = 0
    ) -> Bool {
        assistantPartCount > 0
            || searchActivityCount > 0
            || codeExecutionActivityCount > 0
            || codexToolActivityCount > 0
            || agentToolActivityCount > 0
    }

    @Sendable
    static func run(
        context ctx: SessionContext,
        streamingState: StreamingMessageState,
        callbacks: SessionCallbacks
    ) async {
        await NetworkDebugLogScope.$current.withValue(ctx.networkLogContext) {
            var shouldNotifyCompletion = false
            var completionPreview: String?
            let approvalStore = AgentApprovalSessionStore()

            do {
                guard let providerConfig = ctx.providerConfig else {
                    throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
                }

                var history = prepareHistory(from: ctx)

                let providerManager = ProviderManager()
                let adapter = try await providerManager.createAdapter(for: providerConfig)
                let mcpDefinitionsAndRoutes = try await MCPHub.shared.toolDefinitions(for: ctx.mcpServerConfigs)
                let (mcpTools, mcpRoutes) = mcpDefinitionsAndRoutes
                let (builtinTools, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
                    for: ctx.controlsToUse,
                    useBuiltinSearch: ctx.shouldOfferBuiltinSearch
                )
                let (agentTools, agentRoutes) = await AgentToolHub.shared.toolDefinitions(
                    for: ctx.controlsToUse
                )
                let allTools = mcpTools + builtinTools + agentTools
                let providerType = providerConfig.type

                var requestControls = ctx.controlsToUse
                let optimizedContextCache = await ContextCacheUtilities.applyAutomaticContextCacheOptimizations(
                    adapter: adapter,
                    providerType: providerType,
                    modelID: ctx.modelID,
                    messages: history,
                    controls: requestControls,
                    tools: allTools
                )
                history = optimizedContextCache.messages
                requestControls = optimizedContextCache.controls
                ChatControlNormalizationSupport.sanitizeProviderSpecificForProvider(providerType, controls: &requestControls)

                var iteration = 0
                let agentModeActive = ctx.controlsToUse.agentMode?.enabled == true
                let maxToolIterations = agentModeActive ? 25 : 8

                while iteration < maxToolIterations {
                    try Task.checkCancellation()

                    var accumulator = StreamingResponseAccumulator(providerType: providerConfig.type)
                    var metricsCollector = StreamingResponseMetricsCollector()
                    metricsCollector.begin(at: Date())

                    await MainActor.run {
                        streamingState.reset()
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: ctx.modelID,
                        controls: requestControls,
                        tools: allTools,
                        streaming: ctx.resolvedModelSettings?.capabilities.contains(.streaming) ?? true
                    )

                    var lastUIFlushUptime: TimeInterval = 0
                    var pendingTextDelta = ""
                    var pendingThinkingDelta = ""
                    var streamedCharacterCount = 0

                    func uiFlushInterval() -> TimeInterval {
                        switch streamedCharacterCount {
                        case 0..<4_000:
                            return 0.08
                        case 4_000..<12_000:
                            return 0.10
                        default:
                            return 0.12
                        }
                    }

                    func flushStreamingUI(force: Bool = false) async {
                        let now = ProcessInfo.processInfo.systemUptime
                        guard force || now - lastUIFlushUptime >= uiFlushInterval() else { return }
                        guard force || !pendingTextDelta.isEmpty || !pendingThinkingDelta.isEmpty else { return }

                        lastUIFlushUptime = now
                        let textDelta = pendingTextDelta
                        let thinkingDelta = pendingThinkingDelta
                        pendingTextDelta = ""
                        pendingThinkingDelta = ""

                        await MainActor.run {
                            streamingState.appendDeltas(textDelta: textDelta, thinkingDelta: thinkingDelta)
                        }
                    }

                    for try await event in stream {
                        try Task.checkCancellation()
                        let eventTimestamp = Date()
                        metricsCollector.observe(event: event, at: eventTimestamp)

                        switch event {
                        case .messageStart:
                            break
                        case .contentDelta(let part):
                            if case .text(let delta) = part {
                                accumulator.appendTextDelta(delta)
                                pendingTextDelta.append(delta)
                                streamedCharacterCount += delta.count
                            } else if case .image(let image) = part {
                                accumulator.appendImage(image)
                            } else if case .video(let video) = part {
                                accumulator.appendVideo(video)
                            }
                        case .thinkingDelta(let delta):
                            accumulator.appendThinkingDelta(delta)
                            switch delta {
                            case .thinking(let textDelta, _):
                                if !textDelta.isEmpty {
                                    pendingThinkingDelta.append(textDelta)
                                    streamedCharacterCount += textDelta.count
                                }
                            case .redacted:
                                break
                            }
                        case .toolCallStart(let call):
                            accumulator.upsertToolCall(call)
                            if builtinRoutes.contains(functionName: call.name),
                               let searchActivity = ToolSearchActivityFactory.activityForToolCallStart(
                                   call: call,
                                   providerOverride: builtinRoutes.provider(for: call.name)
                               ) {
                                accumulator.upsertSearchActivity(searchActivity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(searchActivity)
                                }
                            }
                            let visibleToolCalls = accumulator.buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .toolCallDelta:
                            break
                        case .toolCallEnd(let call):
                            accumulator.upsertToolCall(call)
                            let visibleToolCalls = accumulator.buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .searchActivity(let activity):
                            accumulator.upsertSearchActivity(activity)
                            await MainActor.run {
                                streamingState.upsertSearchActivity(activity)
                            }
                        case .codeExecutionActivity(let activity):
                            accumulator.upsertCodeExecutionActivity(activity)
                            await MainActor.run {
                                streamingState.upsertCodeExecutionActivity(activity)
                            }
                        case .codexToolActivity(let activity):
                            accumulator.upsertCodexToolActivity(activity)
                            await MainActor.run {
                                streamingState.upsertCodexToolActivity(activity)
                            }
                        case .codexInteractionRequest(let request):
                            await flushStreamingUI(force: true)
                            await MainActor.run {
                                callbacks.appendCodexInteraction(request, ctx.threadID)
                            }
                        case .codexThreadState(let state):
                            requestControls.codexResumeThreadID = state.remoteThreadID
                            requestControls.codexPendingRollbackTurns = 0
                            await MainActor.run {
                                callbacks.persistCodexThreadState(state, ctx.threadID)
                            }
                        case .claudeManagedSessionState(let state):
                            requestControls.claudeManagedSessionID = state.remoteSessionID
                            requestControls.claudeManagedSessionModelID = state.remoteModelID
                            await MainActor.run {
                                callbacks.persistClaudeManagedSessionState(state, ctx.threadID)
                            }
                        case .claudeManagedCustomToolResults(let results):
                            requestControls.claudeManagedPendingCustomToolResults = results
                            await MainActor.run {
                                callbacks.persistClaudeManagedPendingToolResults(results, ctx.threadID)
                            }
                        case .messageEnd:
                            await MainActor.run {
                                streamingState.markThinkingComplete()
                            }
                        case .error(let err):
                            throw err
                        }

                        await flushStreamingUI()
                    }

                    await flushStreamingUI(force: true)
                    metricsCollector.end(at: Date())

                    let toolCalls = accumulator.buildToolCalls()
                    let assistantParts = accumulator.buildAssistantParts()
                    let searchActivities = accumulator.buildSearchActivities()
                    let codeExecutionActivities = accumulator.buildCodeExecutionActivities()
                    let codexToolActivities = accumulator.buildCodexToolActivities()
                    let agentToolActivities = accumulator.buildAgentToolActivities()
                    let responseMetrics = metricsCollector.metrics
                    var persistedAssistantMessageID: UUID?
                    let hasRenderableAssistantContent = hasRenderableAssistantContent(
                        assistantPartCount: assistantParts.count,
                        searchActivityCount: searchActivities.count,
                        codeExecutionActivityCount: codeExecutionActivities.count,
                        codexToolActivityCount: codexToolActivities.count,
                        agentToolActivityCount: agentToolActivities.count
                    )

                    if hasRenderableAssistantContent || !toolCalls.isEmpty {
                        let persistedParts = await AttachmentImportPipeline.persistImagesToDisk(assistantParts)
                        let assistantMessage = Message(
                            role: .assistant,
                            content: persistedParts,
                            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                            searchActivities: searchActivities.isEmpty ? nil : searchActivities,
                            codeExecutionActivities: codeExecutionActivities.isEmpty ? nil : codeExecutionActivities,
                            codexToolActivities: codexToolActivities.isEmpty ? nil : codexToolActivities,
                            agentToolActivities: agentToolActivities.isEmpty ? nil : agentToolActivities
                        )
                        if let preview = AttachmentImportPipeline.completionNotificationPreview(from: persistedParts) {
                            completionPreview = preview
                        }

                        persistedAssistantMessageID = await MainActor.run {
                            callbacks.persistAssistantMessage(
                                assistantMessage,
                                ctx.providerID,
                                ctx.modelID,
                                ctx.modelNameSnapshot,
                                ctx.threadID,
                                ctx.turnID,
                                responseMetrics
                            )
                        }

                        if toolCalls.isEmpty {
                            await MainActor.run {
                                callbacks.endStreamingSession()
                            }
                        }

                        history.append(assistantMessage)

                        if ctx.triggeredByUserSend,
                           toolCalls.isEmpty,
                           let target = ctx.chatNamingTarget {
                            await callbacks.maybeAutoRename(
                                target.provider,
                                target.modelID,
                                history,
                                assistantMessage
                            )
                        }
                    }

                    let executableToolCalls = toolCalls.filter { !isGoogleProviderNativeToolName($0.name) }

                    guard !executableToolCalls.isEmpty else {
                        shouldNotifyCompletion = hasRenderableAssistantContent
                        break
                    }

                    await MainActor.run {
                        streamingState.reset()
                        streamingState.setToolCalls(executableToolCalls)
                    }

                    let toolExecutionResult = await executeToolCalls(
                        executableToolCalls,
                        context: ctx,
                        accumulator: &accumulator,
                        streamingState: streamingState,
                        callbacks: callbacks,
                        approvalStore: approvalStore,
                        builtinRoutes: builtinRoutes,
                        agentRoutes: agentRoutes,
                        mcpRoutes: mcpRoutes
                    )

                    guard !toolExecutionResult.cancelled else { return }

                    if providerConfig.type == .claudeManagedAgents,
                       !toolExecutionResult.results.isEmpty {
                        let pendingResults = executableToolCalls.compactMap { call -> ClaudeManagedAgentPendingToolResult? in
                            guard let result = toolExecutionResult.results.first(where: { $0.toolCallID == call.id }) else {
                                return nil
                            }
                            return ClaudeManagedAgentPendingToolResult(
                                eventID: call.id,
                                toolCallID: call.providerContextValue(for: "underlying_tool_use_id") ?? call.id,
                                toolName: result.toolName ?? call.name,
                                content: result.content,
                                isError: result.isError,
                                sessionThreadID: call.providerContextValue(for: "session_thread_id")
                            )
                        }
                        requestControls.claudeManagedPendingCustomToolResults = pendingResults
                        await MainActor.run {
                            callbacks.persistClaudeManagedPendingToolResults(pendingResults, ctx.threadID)
                        }
                    }

                    if let assistantMessageID = persistedAssistantMessageID, !toolExecutionResult.searchActivities.isEmpty {
                        await MainActor.run {
                            callbacks.mergeSearchActivities(assistantMessageID, toolExecutionResult.searchActivities)
                        }
                    }

                    let completedAgentActivities = accumulator.buildAgentToolActivities()
                    if let assistantMessageID = persistedAssistantMessageID, !completedAgentActivities.isEmpty {
                        await MainActor.run {
                            callbacks.mergeAgentToolActivities(assistantMessageID, completedAgentActivities)
                        }
                    }

                    let toolMessage = Message(
                        role: .tool,
                        content: toolExecutionResult.outputLines.isEmpty ? [] : [.text(toolExecutionResult.outputLines.joined(separator: "\n\n"))],
                        toolResults: toolExecutionResult.results,
                        searchActivities: toolExecutionResult.searchActivities.isEmpty ? nil : toolExecutionResult.searchActivities
                    )
                    await MainActor.run {
                        callbacks.persistToolMessage(toolMessage, ctx.threadID, ctx.turnID)
                    }
                    history.append(toolMessage)
                    iteration += 1
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    callbacks.showError(error.localizedDescription)
                }
            }
            let shouldNotifyNow = shouldNotifyCompletion
            let previewForNotification = completionPreview
            await MainActor.run {
                callbacks.onSessionEnd(shouldNotifyNow, previewForNotification, ctx.threadID)
            }
        }
    }

    static func prepareHistory(from ctx: SessionContext) -> [Message] {
        let decoder = JSONDecoder()
        var history = ctx.messageSnapshots
            .filter { $0.contextThreadID == ctx.threadID }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { $0.toDomain(using: decoder) }

        if let systemPrompt = ctx.systemPrompt, !systemPrompt.isEmpty {
            history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
        }

        if let maxMessages = ctx.maxHistoryMessages, ctx.shouldTruncateMessages {
            history = ChatContextUsageEstimator.historyCappedByMessageCount(
                history,
                maxHistoryMessages: maxMessages
            )
        }

        if ctx.shouldTruncateMessages {
            history = ChatHistoryTruncator.truncatedHistory(
                history,
                contextWindow: ctx.modelContextWindow,
                reservedOutputTokens: ctx.reservedOutputTokens
            )
        }

        return history
    }
}
