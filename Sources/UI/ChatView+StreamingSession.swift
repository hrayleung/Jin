import Foundation

// MARK: - Streaming Session

extension ChatView {

    @MainActor
    func startStreamingResponse(
        triggeredByUserSend: Bool = false,
        diagnosticRunID: String = UUID().uuidString,
        perMessageMCPServerIDs: Set<String> = []
    ) {
        let conversationID = conversationEntity.id
        // Allow an armed-but-idle session (user bubble already painted with a
        // Generating placeholder) to proceed. Only refuse when a real task is
        // already draining the stream.
        guard !streamingStore.hasActiveStreamingTask(conversationID: conversationID) else { return }

        // Control clicks defer the blob write so the composer can paint first.
        // Send must see the live thinking / search / MCP selection.
        flushGenerationControlsPersist(save: false)

        let threadControls: GenerationControls
        do {
            threadControls = try JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData)
        } catch {
            recordStreamingSetupError("Failed to load conversation settings: \(error.localizedDescription)")
            streamingStore.endSession(conversationID: conversationID)
            return
        }

        let providerSnapshot: ChatStreamingProviderSnapshot
        do {
            providerSnapshot = try ChatStreamingSessionResolver.providerSnapshot(
                for: conversationEntity,
                providers: providers
            )
        } catch {
            recordStreamingSetupError("Failed to load provider configuration: \(error.localizedDescription)")
            streamingStore.endSession(conversationID: conversationID)
            return
        }

        let modelSnapshot = ChatStreamingSessionResolver.modelSnapshot(
            for: conversationEntity,
            threadControls: threadControls,
            providerSnapshot: providerSnapshot,
            managedAgentSyntheticModelID: { providerID, controls in
                managedAgentSyntheticModelID(providerID: providerID, controls: controls)
            },
            effectiveModelID: { modelID, providerEntity, providerType in
                effectiveModelID(for: modelID, providerEntity: providerEntity, providerType: providerType)
            },
            migrateConversationModelIDIfNeeded: { conversation, resolvedModelID in
                guard resolvedModelID != conversation.modelID else { return }
                conversation.modelID = resolvedModelID
                conversation.updatedAt = Date()
                try? modelContext.save()
            },
            resolvedModelInfo: { modelID, providerEntity, providerType in
                resolvedModelInfo(for: modelID, providerEntity: providerEntity, providerType: providerType)
            },
            normalizedModelInfo: { modelInfo, providerType in
                normalizedModelInfo(modelInfo, for: providerType)
            }
        )

        let streamingState = streamingStore.beginSession(
            conversationID: conversationID,
            modelLabel: modelSnapshot.modelName,
            modelID: modelSnapshot.modelID
        )
        streamingState.debugContext = StreamingDebugContext(
            conversationID: conversationID,
            diagnosticRunID: diagnosticRunID
        )
        // Early-armed sessions are already empty — skip a redundant
        // objectWillChange that would re-invalidate the just-painted row.
        if streamingState.renderTick != 0
            || streamingState.hasVisibleText
            || !streamingState.thinkingChunks.isEmpty
            || !streamingState.streamingToolCalls.isEmpty
            || !streamingState.searchActivities.isEmpty
            || !streamingState.codeExecutionActivities.isEmpty
            || !streamingState.artifacts.isEmpty {
            streamingState.reset()
        }

        // Prefer in-memory render-cache history on the send hot path, but only
        // when it is complete and count-aligned with the conversation.
        // `clearForConversationSwitch` leaves `isHistoryReady == true` with an
        // empty history; provisional tail paint also leaves history empty until
        // the full decode lands. Using that cache would drop prior turns from
        // the provider request.
        let snapshotBuildStartedAt = ProcessInfo.processInfo.systemUptime
        let expectedHistoryCount = conversationEntity.resolvedMessageCount
        let cachedHistory = renderCache.activeThreadHistory
        let canUsePrebuiltHistory = renderCache.isHistoryReady
            && cachedHistory.count == expectedHistoryCount
        let prebuiltHistory: [Message]?
        let messageSnapshots: [PersistedMessageSnapshot]
        if canUsePrebuiltHistory {
            prebuiltHistory = cachedHistory
            messageSnapshots = []
        } else {
            prebuiltHistory = nil
            messageSnapshots = orderedConversationMessages().map(PersistedMessageSnapshot.init)
        }
        let snapshotBuildDurationMs = Int((ProcessInfo.processInfo.systemUptime - snapshotBuildStartedAt) * 1000)

        // #region agent log
        ChatDiagnosticLogger.log(
            runId: diagnosticRunID,
            hypothesisId: "H2",
            message: "chat_stream_context_ready",
            data: [
                "conversationID": conversationID.uuidString,
                "triggeredByUserSend": String(triggeredByUserSend),
                "snapshotCount": String(messageSnapshots.count),
                "prebuiltHistoryCount": String(prebuiltHistory?.count ?? 0),
                "usedPrebuiltHistory": String(canUsePrebuiltHistory),
                "expectedHistoryCount": String(expectedHistoryCount),
                "conversationMessageCount": String(conversationEntity.resolvedMessageCount),
                "durationMs": String(snapshotBuildDurationMs)
            ]
        )
        // #endregion
        let assistant = conversationEntity.assistant
        let systemPrompt = resolvedSystemPrompt(
            conversationSystemPrompt: conversationEntity.systemPrompt,
            assistant: assistant
        )
        let controlsToUse = ChatStreamingSessionResolver.requestControls(
            threadControls: threadControls,
            assistant: assistant,
            modelSnapshot: modelSnapshot,
            providerType: providerSnapshot.type,
            automaticContextCacheControls: { providerType, modelID, modelCapabilities in
                automaticContextCacheControls(
                    providerType: providerType,
                    modelID: modelID,
                    modelCapabilities: modelCapabilities
                )
            },
            sanitizeProviderSpecific: Self.sanitizeProviderSpecificForProvider,
            injectClaudeManagedAgentSessionPersistence: { controls in
                injectClaudeManagedAgentSessionPersistence(into: &controls)
            }
        )
        let historySettings = ChatStreamingSessionResolver.historySettings(
            assistant: assistant,
            modelSnapshot: modelSnapshot,
            controls: controlsToUse
        )
        let threadSupportsPerMessageMCP = threadSupportsMCPTools(
            providerType: providerSnapshot.type,
            resolvedModelSettings: modelSnapshot.resolvedSettings
        )
        let mcpServerConfigs: [MCPServerConfig]
        do {
            mcpServerConfigs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
                controls: controlsToUse,
                supportsMCPToolsControl: threadSupportsPerMessageMCP,
                servers: mcpServers,
                perMessageOverrideServerIDs: perMessageMCPServerIDs
            )
        } catch {
            recordStreamingSetupError("Failed to load MCP server configs: \(error.localizedDescription)")
            streamingStore.endSession(conversationID: conversationID)
            return
        }
        let chatNamingTarget = resolvedChatNamingTarget()
        let shouldOfferBuiltinSearch = ChatStreamingSessionResolver.shouldOfferBuiltinSearch(
            providerType: providerSnapshot.type,
            modelID: modelSnapshot.modelID,
            resolvedModelSettings: modelSnapshot.resolvedSettings,
            controls: controlsToUse,
            webSearchPluginEnabled: webSearchPluginEnabled,
            webSearchPluginConfigured: webSearchPluginConfigured
        )
        let networkLogContext = NetworkDebugLogContext(
            conversationID: conversationID.uuidString
        )

        responseCompletionNotifier.prepareAuthorizationIfNeededWhileActive()

        let sessionContext = ChatStreamingOrchestrator.SessionContext(
            conversationID: conversationID,
            diagnosticRunID: diagnosticRunID,
            providerID: providerSnapshot.providerID,
            providerConfig: providerSnapshot.config,
            providerType: providerSnapshot.type,
            modelID: modelSnapshot.modelID,
            modelNameSnapshot: modelSnapshot.modelName,
            resolvedModelSettings: modelSnapshot.resolvedSettings,
            messageSnapshots: messageSnapshots,
            prebuiltHistory: prebuiltHistory,
            systemPrompt: systemPrompt,
            controlsToUse: controlsToUse,
            shouldTruncateMessages: historySettings.shouldTruncateMessages,
            maxHistoryMessages: historySettings.maxHistoryMessages,
            modelContextWindow: historySettings.modelContextWindow,
            reservedOutputTokens: historySettings.reservedOutputTokens,
            mcpServerConfigs: mcpServerConfigs,
            chatNamingTarget: chatNamingTarget,
            shouldOfferBuiltinSearch: shouldOfferBuiltinSearch,
            triggeredByUserSend: triggeredByUserSend,
            networkLogContext: networkLogContext
        )

        let toolTurnHandoff = ToolTurnPersistHandoff()

        let sessionCallbacks = ChatStreamingOrchestrator.SessionCallbacks(
            persistAssistantMessage: { [self] message, providerID, modelID, modelName, metrics in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.generatedProviderID = providerID
                    entity.generatedModelID = modelID
                    entity.generatedModelName = modelName
                    entity.responseMetrics = metrics
                    entity.conversation = conversationEntity

                    // A completed response must be durable before optional
                    // display preparation. In particular, a pathological
                    // Markdown parse must never leave the only copy in the
                    // transient streaming row if the app exits mid-prewarm.
                    let shouldPrepareDisplay = message.toolCalls?.isEmpty != false
                    let isToolRequestingTurn = message.toolCalls?.isEmpty == false
                    // Always defer observers for this persist. Tool-requesting
                    // turns keep the defer armed past return so the queued
                    // count/updatedAt onChange cannot start a second decode.
                    defersObservedMessageCacheRebuild = true
                    defer {
                        if !isToolRequestingTurn {
                            defersObservedMessageCacheRebuild = false
                        }
                    }

                    conversationEntity.messages.append(entity)
                    conversationEntity.refreshMessageCount()
                    conversationEntity.updatedAt = Date()
                    // One more visible row joins the suffix window. Without
                    // this the window slides at stream end (head drops, tail
                    // appends) — the same batchDiff churn the send path grows
                    // the window to avoid, just moved one turn later.
                    expandRenderWindowForPinnedSendIfNeeded(additionalMessages: 1)
                    persistCompletedAssistantMessage()

                    // Keep the already-rendered streaming row alive until the
                    // exact persisted-row cache keys are ready. Observer-driven
                    // cache rebuilds are deferred above, but the SwiftData save
                    // has already completed before this best-effort UI work.
                    if shouldPrepareDisplay {
                        let prewarmItems = ChatMessageRenderPipeline.markdownPrewarmItems(
                            for: message,
                            artifactsEnabled: conversationEntity.artifactsEnabled == true
                        )
                        if !prewarmItems.isEmpty {
                            let defaults = UserDefaults.standard
                            let appFontFamily = defaults.string(forKey: AppPreferenceKeys.appFontFamily)
                                ?? JinTypography.systemFontPreferenceValue
                            let codeFontFamily = defaults.string(forKey: AppPreferenceKeys.codeFontFamily)
                                ?? JinTypography.systemFontPreferenceValue
                            await NativeMarkdownCache.prepareForImmediateDisplay(
                                items: prewarmItems,
                                appFontFamily: appFontFamily,
                                codeFontFamily: codeFontFamily
                            )
                        }
                    }

                    // Handoff BEFORE the cache rebuild so the timeline never
                    // paints the same tool turn twice: the persisted row
                    // appears in the same MainActor turn the live bubble
                    // is cleared. Do not re-attach the calls on the live
                    // state — that is the duplicate Running card.
                    if isToolRequestingTurn {
                        streamingStore.streamingState(conversationID: conversationID)?.reset()
                        toolTurnHandoff.skipDebouncedRebuild = true
                    } else {
                        defersObservedMessageCacheRebuild = false
                    }
                    rebuildMessageCaches()
                    autoOpenLatestArtifactIfNeeded(from: message)
                    return entity.id
                } catch {
                    presentError(error.localizedDescription)
                    return nil
                }
            },
            persistToolMessage: { [self] message in
                persistStreamingToolMessage(
                    message,
                    scheduleCacheRebuild: !toolTurnHandoff.skipDebouncedRebuild
                )
                toolTurnHandoff.skipDebouncedRebuild = false
            },
            persistClaudeManagedSessionState: { [self] state in
                persistClaudeManagedAgentSessionState(state)
            },
            persistClaudeManagedPendingToolResults: { [self] results in
                persistClaudeManagedPendingCustomToolResults(results)
            },
            appendManagedAgentInteraction: { [self] request in
                pendingManagedAgentInteractions.append(PendingManagedAgentInteraction(request: request))
            },
            mergeSearchActivities: { [self] messageID, activities in
                mergeSearchActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            upsertLiveToolResult: { [self] result, resultConversationID in
                renderCache.upsertLiveToolResult(result, conversationID: resultConversationID)
            },
            maybeAutoRename: { [self] provider, targetModelID, history, assistantMessage in
                await maybeAutoRenameConversation(
                    targetProvider: provider,
                    targetModelID: targetModelID,
                    history: history,
                    finalAssistantMessage: assistantMessage
                )
            },
            showError: { [self] presentation in
                presentError(presentation)
            },
            endStreamingSession: { [self] in
                streamingStore.endSession(conversationID: conversationID)
            },
            onSessionEnd: { [self] shouldNotify, preview in
                defersObservedMessageCacheRebuild = false
                toolTurnHandoff.skipDebouncedRebuild = false
                if shouldNotify {
                    responseCompletionNotifier.notifyCompletionIfNeeded(
                        conversationID: conversationID,
                        conversationTitle: conversationEntity.title,
                        replyPreview: preview
                    )
                }
                streamingStore.endSession(conversationID: conversationID)
                pendingManagedAgentInteractions.removeAll()
                rebuildMessageCachesIfNeeded()
                flushPendingPersistenceSave()
            }
        )

        let task = Task.detached(priority: .userInitiated) {
            await ChatStreamingOrchestrator.run(
                context: sessionContext,
                streamingState: streamingState,
                callbacks: sessionCallbacks
            )
        }
        streamingStore.attachTask(task, conversationID: conversationID)
    }

    @MainActor
    private func recordStreamingSetupError(_ message: String) {
        streamingStore.recordError(conversationID: conversationEntity.id, message: message)
        presentError(message)
    }

    // MARK: - Debounced SwiftData persistence

    /// Coalesces SwiftData writes during streaming. Each call resets a 500ms
    /// timer; if streaming is generating messages faster than that we save at
    /// most once per quiet window. Must be paired with `flushPendingPersistenceSave`
    /// at session end so a final commit always lands.
    @MainActor
    func schedulePersistenceSave() {
        pendingPersistenceSaveTask?.cancel()
        pendingPersistenceSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistModelContext(context: "debounced streaming save")
        }
    }

    /// Persists a hidden `.tool` follow-up. After a tool-requesting assistant
    /// persist the timeline already rebuilt once; skip the 120ms decode so
    /// observers cannot start a second full apply for the same handoff.
    @MainActor
    func persistStreamingToolMessage(
        _ message: Message,
        scheduleCacheRebuild: Bool
    ) {
        do {
            let entity = try MessageEntity.fromDomain(message)
            entity.conversation = conversationEntity
            if !scheduleCacheRebuild {
                defersObservedMessageCacheRebuild = true
            }
            conversationEntity.messages.append(entity)
            conversationEntity.refreshMessageCount()
            conversationEntity.updatedAt = Date()
            if scheduleCacheRebuild {
                renderCache.scheduleDebouncedRebuild(after: .milliseconds(120)) {
                    rebuildMessageCachesIfNeeded()
                }
            } else {
                // onChange is queued for this mutation. Keep the defer armed
                // until the next main-queue pass so it still no-ops.
                DispatchQueue.main.async {
                    self.defersObservedMessageCacheRebuild = false
                }
            }
            schedulePersistenceSave()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    /// Saves completed assistant content immediately, before any optional UI
    /// prewarm can suspend. It also retires an older debounced save because the
    /// synchronous commit covers every pending change in this model context.
    @MainActor
    private func persistCompletedAssistantMessage() {
        pendingPersistenceSaveTask?.cancel()
        pendingPersistenceSaveTask = nil
        persistModelContext(context: "assistant completion before markdown prewarm")
    }

    /// Cancels any pending debounced save and commits synchronously. Called on
    /// session end and on conversation switch / chat disappearance.
    @MainActor
    func flushPendingPersistenceSave() {
        pendingPersistenceSaveTask?.cancel()
        pendingPersistenceSaveTask = nil
        flushGenerationControlsPersist(save: false)
        persistModelContext(context: "streaming save flush")
    }

    @MainActor
    private func persistModelContext(context: String) {
        do {
            try modelContext.save()
        } catch {
            let message = "Failed to save chat: \(error.localizedDescription)"
            presentError(message)
            ChatDiagnosticLogger.log(
                runId: conversationEntity.id.uuidString,
                hypothesisId: "persistence",
                message: "chat_persistence_save_failed",
                data: [
                    "conversationID": conversationEntity.id.uuidString,
                    "context": context,
                    "error": error.localizedDescription
                ]
            )
        }
    }
}

/// Session-scoped flag so `persistToolMessage` can skip a second decode after
/// the tool-requesting assistant persist already rebuilt the timeline.
@MainActor
private final class ToolTurnPersistHandoff {
    var skipDebouncedRebuild = false
}
