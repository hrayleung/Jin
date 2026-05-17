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
        guard !streamingStore.isStreaming(conversationID: conversationID) else { return }

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
        streamingState.reset()
        let snapshotBuildStartedAt = ProcessInfo.processInfo.systemUptime
        let messageSnapshots = orderedConversationMessages().map(PersistedMessageSnapshot.init)
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
            persistAssistantMessage: { [self] message, providerID, modelID, modelName, metrics in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.generatedProviderID = providerID
                    entity.generatedModelID = modelID
                    entity.generatedModelName = modelName
                    entity.responseMetrics = metrics
                    entity.conversation = conversationEntity
                    conversationEntity.messages.append(entity)
                    conversationEntity.updatedAt = Date()
                    rebuildMessageCaches()
                    autoOpenLatestArtifactIfNeeded(from: message)
                    schedulePersistenceSave()
                    return entity.id
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                    return nil
                }
            },
            persistToolMessage: { [self] message in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.conversation = conversationEntity
                    conversationEntity.messages.append(entity)
                    conversationEntity.updatedAt = Date()
                    renderCache.scheduleDebouncedRebuild(after: .milliseconds(120)) {
                        rebuildMessageCachesIfNeeded()
                    }
                    schedulePersistenceSave()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
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
                streamingStore.endSession(conversationID: conversationID)
            },
            onSessionEnd: { [self] shouldNotify, preview in
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
        errorMessage = message
        showingError = true
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

    /// Cancels any pending debounced save and commits synchronously. Called on
    /// session end and on conversation switch / chat disappearance.
    @MainActor
    func flushPendingPersistenceSave() {
        pendingPersistenceSaveTask?.cancel()
        pendingPersistenceSaveTask = nil
        persistModelContext(context: "streaming save flush")
    }

    @MainActor
    private func persistModelContext(context: String) {
        do {
            try modelContext.save()
        } catch {
            let message = "Failed to save chat: \(error.localizedDescription)"
            errorMessage = message
            showingError = true
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
