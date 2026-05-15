import Foundation

// MARK: - Streaming Session

extension ChatView {

    @MainActor
    func startStreamingResponse(
        for threadID: UUID,
        triggeredByUserSend: Bool = false,
        turnID: UUID? = nil,
        diagnosticRunID: String = UUID().uuidString,
        perMessageMCPServerIDs: Set<String> = []
    ) {
        let conversationID = conversationEntity.id
        guard !streamingStore.isStreaming(conversationID: conversationID, threadID: threadID) else { return }

        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        let threadControls: GenerationControls
        do {
            threadControls = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        } catch {
            streamingStore.recordError(
                conversationID: conversationID,
                threadID: threadID,
                message: "Failed to load conversation settings: \(error.localizedDescription)"
            )
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            return
        }

        let providerSnapshot: ChatStreamingProviderSnapshot
        do {
            providerSnapshot = try ChatStreamingSessionResolver.providerSnapshot(
                for: thread,
                providers: providers
            )
        } catch {
            streamingStore.recordError(
                conversationID: conversationID,
                threadID: threadID,
                message: "Failed to load provider configuration: \(error.localizedDescription)"
            )
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            return
        }

        let modelSnapshot = ChatStreamingSessionResolver.modelSnapshot(
            for: thread,
            threadControls: threadControls,
            providerSnapshot: providerSnapshot,
            managedAgentSyntheticModelID: { providerID, controls in
                managedAgentSyntheticModelID(providerID: providerID, controls: controls)
            },
            effectiveModelID: { modelID, providerEntity, providerType in
                effectiveModelID(for: modelID, providerEntity: providerEntity, providerType: providerType)
            },
            migrateThreadModelIDIfNeeded: { thread, resolvedModelID in
                migrateThreadModelIDIfNeeded(thread, resolvedModelID: resolvedModelID)
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
            threadID: threadID,
            modelLabel: modelSnapshot.modelName,
            modelID: modelSnapshot.modelID
        )
        streamingState.debugContext = StreamingDebugContext(
            conversationID: conversationID,
            threadID: threadID,
            diagnosticRunID: diagnosticRunID
        )
        streamingState.reset()
        let snapshotBuildStartedAt = ProcessInfo.processInfo.systemUptime
        let messageSnapshots = orderedConversationMessages(threadID: threadID).map(PersistedMessageSnapshot.init)
        let snapshotBuildDurationMs = Int((ProcessInfo.processInfo.systemUptime - snapshotBuildStartedAt) * 1000)

        // #region agent log
        ChatDiagnosticLogger.log(
            runId: diagnosticRunID,
            hypothesisId: "H2",
            message: "chat_stream_context_ready",
            data: [
                "conversationID": conversationID.uuidString,
                "threadID": threadID.uuidString,
                "triggeredByUserSend": String(triggeredByUserSend),
                "snapshotCount": String(messageSnapshots.count),
                "conversationMessageCount": String(conversationEntity.messages.count),
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
                injectClaudeManagedAgentSessionPersistence(into: &controls, from: thread)
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
            streamingStore.recordError(
                conversationID: conversationID,
                threadID: threadID,
                message: "Failed to load MCP server configs: \(error.localizedDescription)"
            )
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
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
            conversationID: conversationID.uuidString,
            threadID: threadID.uuidString,
            turnID: turnID?.uuidString
        )

        responseCompletionNotifier.prepareAuthorizationIfNeededWhileActive()

        let sessionContext = ChatStreamingOrchestrator.SessionContext(
            conversationID: conversationID,
            threadID: threadID,
            turnID: turnID,
            diagnosticRunID: diagnosticRunID,
            providerID: providerSnapshot.providerID,
            providerConfig: providerSnapshot.config,
            providerType: providerSnapshot.type,
            modelID: modelSnapshot.modelID,
            modelNameSnapshot: modelSnapshot.modelName,
            resolvedModelSettings: modelSnapshot.resolvedSettings,
            messageSnapshots: messageSnapshots,
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

        let sessionCallbacks = ChatStreamingOrchestrator.SessionCallbacks(
            persistAssistantMessage: { [self] message, providerID, modelID, modelName, threadID, turnID, metrics in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.generatedProviderID = providerID
                    entity.generatedModelID = modelID
                    entity.generatedModelName = modelName
                    entity.contextThreadID = threadID
                    entity.turnID = turnID
                    entity.responseMetrics = metrics
                    entity.conversation = conversationEntity
                    conversationEntity.messages.append(entity)
                    conversationEntity.updatedAt = Date()
                    // Assistant rebuilds must remain synchronous so that
                    // `autoOpenLatestArtifactIfNeeded` sees the fresh artifact
                    // catalog before it inspects it.
                    rebuildMessageCaches()
                    autoOpenLatestArtifactIfNeeded(from: message, threadID: threadID)
                    schedulePersistenceSave()
                    return entity.id
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                    return nil
                }
            },
            persistToolMessage: { [self] message, threadID, turnID in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.contextThreadID = threadID
                    entity.turnID = turnID
                    entity.conversation = conversationEntity
                    conversationEntity.messages.append(entity)
                    conversationEntity.updatedAt = Date()
                    // Tool messages can land many-per-second on heavy turns.
                    // Coalesce both the rebuild and the SwiftData save.
                    renderCache.scheduleDebouncedRebuild(after: .milliseconds(120)) {
                        rebuildMessageCachesIfNeeded()
                    }
                    schedulePersistenceSave()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            },
            persistClaudeManagedSessionState: { [self] state, localThreadID in
                persistClaudeManagedAgentSessionState(state, forLocalThreadID: localThreadID)
            },
            persistClaudeManagedPendingToolResults: { [self] results, localThreadID in
                persistClaudeManagedPendingCustomToolResults(results, forLocalThreadID: localThreadID)
            },
            appendManagedAgentInteraction: { [self] request, localThreadID in
                pendingManagedAgentInteractions.append(PendingManagedAgentInteraction(localThreadID: localThreadID, request: request))
            },
            mergeSearchActivities: { [self] messageID, activities in
                mergeSearchActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            maybeAutoRename: { [self] provider, targetModelID, history, assistantMessage in
                await maybeAutoRenameConversation(
                    targetProvider: provider,
                    targetModelID: targetModelID,
                    history: history,
                    finalAssistantMessage: assistantMessage
                )
            },
            showError: { [self] message in
                errorMessage = message
                showingError = true
            },
            endStreamingSession: { [self] in
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            },
            onSessionEnd: { [self] shouldNotify, preview, sessionThreadID in
                if shouldNotify {
                    responseCompletionNotifier.notifyCompletionIfNeeded(
                        conversationID: conversationID,
                        conversationTitle: conversationEntity.title,
                        replyPreview: preview
                    )
                }
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                pendingManagedAgentInteractions.removeAll { $0.localThreadID == sessionThreadID }
                // Flush the debounced rebuild so the final tool result is
                // reflected immediately, then commit the SwiftData save so a
                // crash after this point doesn't lose the finished turn.
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
        streamingStore.attachTask(task, conversationID: conversationID, threadID: threadID)
    }

    // MARK: - Debounced SwiftData persistence

    /// Coalesces SwiftData writes during streaming. Each call resets a 500ms
    /// timer; if streaming is generating messages faster than that we save at
    /// most once per quiet window. Must be paired with `flushPendingPersistenceSave`
    /// at session end so a final commit always lands.
    @MainActor
    func schedulePersistenceSave() {
        pendingPersistenceSaveTask?.cancel()
        let modelContext = modelContext
        pendingPersistenceSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    /// Cancels any pending debounced save and commits synchronously. Called on
    /// session end and on conversation switch / chat disappearance.
    @MainActor
    func flushPendingPersistenceSave() {
        pendingPersistenceSaveTask?.cancel()
        pendingPersistenceSaveTask = nil
        try? modelContext.save()
    }
}
