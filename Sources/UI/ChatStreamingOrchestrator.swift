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

                if let maxMessages = ctx.maxHistoryMessages, ctx.shouldTruncateMessages, history.count > maxMessages {
                    let systemMessages = history.prefix(while: { $0.role == .system })
                    let nonSystemMessages = history.drop(while: { $0.role == .system })
                    let kept = Array(nonSystemMessages.suffix(maxMessages))
                    history = Array(systemMessages) + kept
                }

                if ctx.shouldTruncateMessages {
                    history = ChatHistoryTruncator.truncatedHistory(
                        history,
                        contextWindow: ctx.modelContextWindow,
                        reservedOutputTokens: ctx.reservedOutputTokens
                    )
                }

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
                                        return
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

                    let toolSearchActivities = Array(toolSearchActivitiesByID.values)
                    if let assistantMessageID = persistedAssistantMessageID, !toolSearchActivities.isEmpty {
                        await MainActor.run {
                            callbacks.mergeSearchActivities(assistantMessageID, toolSearchActivities)
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
                        content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))],
                        toolResults: toolResults,
                        searchActivities: toolSearchActivities.isEmpty ? nil : toolSearchActivities
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

    // MARK: - Agent Approval Helpers

    private static func agentToolNeedsApproval(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls,
        approvalKey: String?,
        approvalStore: AgentApprovalSessionStore
    ) async -> Bool {
        if controls.bypassPermissions { return false }
        if let approvalKey, await approvalStore.isApproved(key: approvalKey) {
            return false
        }

        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            guard let command = raw["command"] as? String else { return true }
            return !AgentCommandAllowlist.isCommandAllowed(
                command,
                allowedPrefixes: controls.allowedCommandPrefixes
            )
        case AgentToolHub.fileReadFunctionName:
            return !controls.autoApproveFileReads
        case AgentToolHub.fileWriteFunctionName, AgentToolHub.fileEditFunctionName:
            return true
        case AgentToolHub.globSearchFunctionName, AgentToolHub.grepSearchFunctionName:
            return false
        default:
            return true
        }
    }

    private static func makeAgentApprovalRequest(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> AgentApprovalRequest {
        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            let command = raw["command"] as? String ?? "(unknown)"
            let cwd = (raw["working_directory"] as? String)
                ?? (raw["workingDirectory"] as? String)
                ?? (raw["cwd"] as? String)
                ?? controls.workingDirectory
            return AgentApprovalRequest(kind: .shellCommand(command: command, cwd: cwd))

        case AgentToolHub.fileWriteFunctionName:
            let path = raw["path"] as? String ?? "(unknown)"
            let content = raw["content"] as? String ?? ""
            let preview = String(content.prefix(2048))
            return AgentApprovalRequest(kind: .fileWrite(path: path, preview: preview))

        case AgentToolHub.fileEditFunctionName:
            let path = raw["path"] as? String ?? "(unknown)"
            let oldText = raw["old_text"] as? String ?? ""
            let newText = raw["new_text"] as? String ?? ""
            return AgentApprovalRequest(kind: .fileEdit(
                path: path,
                oldText: String(oldText.prefix(2048)),
                newText: String(newText.prefix(2048))
            ))

        default:
            return AgentApprovalRequest(kind: .shellCommand(command: "(unknown)", cwd: nil))
        }
    }

    static func agentApprovalSessionKey(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> String? {
        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            guard let command = normalizedStringValue(raw["command"] ?? raw["cmd"]) else { return nil }
            let cwd = normalizedStringValue(raw["working_directory"] ?? raw["workingDirectory"] ?? raw["cwd"])
                ?? controls.workingDirectory
                ?? ""
            return "shell:\(cwd):\(command)"

        case AgentToolHub.fileReadFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]) else { return nil }
            let offset = normalizedStringValue(raw["offset"] ?? raw["line_offset"] ?? raw["start_line"]) ?? ""
            let limit = normalizedStringValue(raw["limit"] ?? raw["line_count"] ?? raw["max_lines"]) ?? ""
            return "file_read:\(path):\(offset):\(limit)"

        case AgentToolHub.fileWriteFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]),
                  let content = normalizedStringValue(raw["content"] ?? raw["text"] ?? raw["data"]) else {
                return nil
            }
            return "file_write:\(path):\(sha256Hex(content))"

        case AgentToolHub.fileEditFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]),
                  let oldText = normalizedStringValue(raw["old_text"] ?? raw["oldText"] ?? raw["old_string"] ?? raw["search"]),
                  let newText = normalizedStringValue(raw["new_text"] ?? raw["newText"] ?? raw["new_string"] ?? raw["replace"]) else {
                return nil
            }
            return "file_edit:\(path):\(sha256Hex(oldText)):\(sha256Hex(newText))"

        default:
            return nil
        }
    }

    private static func normalizedStringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(Int(double))
        default:
            return nil
        }
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
