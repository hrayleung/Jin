import Collections
import SwiftUI
import SwiftData

// MARK: - Send, Streaming & Naming

extension ChatView {

    func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let basePrompt = ChatMessagePreparationSupport.resolvedSystemPrompt(
            conversationSystemPrompt: conversationSystemPrompt,
            assistant: assistant
        )

        return ArtifactMarkupParser.appendingInstructions(
            to: basePrompt,
            enabled: conversationEntity.artifactsEnabled == true
        )
    }

    func sendMessage() {
        sendMessageInternal()
    }

    func sendMessageInternal() {
        let diagnosticRunID = UUID().uuidString
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: diagnosticRunID,
            hypothesisId: "H4",
            message: "chat_send_entry",
            data: [
                "conversationID": conversationEntity.id.uuidString,
                "messageCount": String(conversationEntity.messages.count),
                "isStreaming": String(isStreaming),
                "isPreparingToSend": String(isPreparingToSend),
                "isImportingDropAttachments": String(isImportingDropAttachments),
                "canSendDraft": String(canSendDraft)
            ]
        )
        // #endregion
        if isStreaming {
            streamingStore.cancel(conversationID: conversationEntity.id)
            return
        }

        if isPreparingToSend {
            prepareToSendCancellationReason = .userCancelled
            prepareToSendTask?.cancel()
            return
        }

        guard !isImportingDropAttachments else { return }
        guard canSendDraft else { return }
        endEditingUI()
        ensureModelThreadsInitializedIfNeeded()

        guard let activeThread = activeModelThread else {
            errorMessage = "No active model is available for this chat."
            showingError = true
            return
        }

        let targetThreadIDs = selectedModelThreads.map(\.id)
        guard !targetThreadIDs.isEmpty else {
            errorMessage = "Please add a model before sending."
            showingError = true
            return
        }
        let targetThreads = targetThreadIDs.compactMap { targetID in
            sortedModelThreads.first(where: { $0.id == targetID })
        }
        guard !targetThreads.isEmpty else {
            errorMessage = "Please add a model before sending."
            showingError = true
            return
        }
        let namingThreadID = targetThreadIDs.contains(activeThread.id) ? activeThread.id : targetThreadIDs.first

        let selectedPerMessageMCPServers = eligibleMCPServers
            .filter { perMessageMCPServerIDs.contains($0.id) }
            .map { (id: $0.id, name: $0.name) }
        let draftSnapshot = ChatSendDraftSnapshot(
            messageText: trimmedMessageText,
            remoteVideoURLText: trimmedRemoteVideoInputURLText,
            attachments: draftAttachments,
            quotes: draftQuotes,
            selectedPerMessageMCPServers: selectedPerMessageMCPServers
        )

        let remoteVideoURLSnapshot: URL?
        do {
            remoteVideoURLSnapshot = try resolvedRemoteVideoInputURL(from: draftSnapshot.remoteVideoURLText)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        messageText = ""
        remoteVideoInputURLText = ""
        composerTextContentHeight = 36
        draftAttachments = []
        draftQuotes = []

        isPreparingToSend = true
        prepareToSendStatus = nil
        prepareToSendCancellationReason = nil

        let task = Task {
            do {
                let prepareStartedAt = ProcessInfo.processInfo.systemUptime
                let preparedMessages = try await buildUserMessagePartsForThreads(
                    threads: targetThreads,
                    quoteContents: draftSnapshot.quoteContents,
                    messageText: draftSnapshot.messageText,
                    attachments: draftSnapshot.attachments,
                    remoteVideoURL: remoteVideoURLSnapshot
                )
                let prepareDurationMs = Int((ProcessInfo.processInfo.systemUptime - prepareStartedAt) * 1000)

                // #region agent log
                ChatDiagnosticLogger.log(
                    runId: diagnosticRunID,
                    hypothesisId: "H3",
                    message: "chat_prepare_complete",
                    data: [
                        "conversationID": conversationEntity.id.uuidString,
                        "turnID": draftSnapshot.turnID.uuidString,
                        "preparedThreadCount": String(preparedMessages.count),
                        "targetThreadCount": String(targetThreads.count),
                        "attachmentCount": String(draftSnapshot.attachments.count),
                        "quoteCount": String(draftSnapshot.quotes.count),
                        "textCount": String(draftSnapshot.messageText.count),
                        "durationMs": String(prepareDurationMs)
                    ]
                )
                // #endregion

                await MainActor.run {
                    let persistBlockStartedAt = ProcessInfo.processInfo.systemUptime

                    // #region agent log
                    ChatDiagnosticLogger.log(
                        runId: diagnosticRunID,
                        hypothesisId: "H1",
                        message: "chat_persist_block_start",
                        data: [
                            "conversationID": conversationEntity.id.uuidString,
                            "turnID": draftSnapshot.turnID.uuidString,
                            "messageCountBeforePersist": String(conversationEntity.messages.count),
                            "preparedMessageCount": String(preparedMessages.count)
                        ]
                    )
                    // #endregion

                    let toolCapableThreadIDs = Set(targetThreads.compactMap { threadSupportsMCPTools(for: $0) ? $0.id : nil })
                    let rebuildStartedAt = ProcessInfo.processInfo.systemUptime
                    ChatUserTurnPersistence.appendPreparedUserMessages(
                        preparedMessages,
                        draft: draftSnapshot,
                        toolCapableThreadIDs: toolCapableThreadIDs,
                        conversationEntity: conversationEntity,
                        isChatNamingPluginEnabled: isChatNamingPluginEnabled,
                        persistConversationIfNeeded: onPersistConversationIfNeeded,
                        makeConversationTitle: makeConversationTitle(from:),
                        rebuildMessageCaches: rebuildMessageCaches
                    )
                    let rebuildDurationMs = Int((ProcessInfo.processInfo.systemUptime - rebuildStartedAt) * 1000)

                    // #region agent log
                    ChatDiagnosticLogger.log(
                        runId: diagnosticRunID,
                        hypothesisId: "H1",
                        message: "chat_persist_rebuild_complete",
                        data: [
                            "conversationID": conversationEntity.id.uuidString,
                            "turnID": draftSnapshot.turnID.uuidString,
                            "messageCountAfterAppend": String(conversationEntity.messages.count),
                            "cachedVisibleCount": String(renderCache.visibleMessages.count),
                            "cachedHistoryCount": String(renderCache.activeThreadHistory.count),
                            "historyCacheReady": String(renderCache.isHistoryReady),
                            "durationMs": String(rebuildDurationMs)
                        ]
                    )
                    // #endregion

                    let saveStartedAt = ProcessInfo.processInfo.systemUptime
                    try? modelContext.save()
                    let saveDurationMs = Int((ProcessInfo.processInfo.systemUptime - saveStartedAt) * 1000)
                    let totalPersistDurationMs = Int((ProcessInfo.processInfo.systemUptime - persistBlockStartedAt) * 1000)

                    // #region agent log
                    ChatDiagnosticLogger.log(
                        runId: diagnosticRunID,
                        hypothesisId: "H1",
                        message: "chat_persist_save_complete",
                        data: [
                            "conversationID": conversationEntity.id.uuidString,
                            "turnID": draftSnapshot.turnID.uuidString,
                            "messageCountAfterSave": String(conversationEntity.messages.count),
                            "saveDurationMs": String(saveDurationMs),
                            "totalPersistDurationMs": String(totalPersistDurationMs)
                        ]
                    )
                    // #endregion
                }

                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    prepareToSendCancellationReason = nil
                    perMessageMCPServerIDs = []
                    for threadID in targetThreadIDs {
                        startStreamingResponse(
                            for: threadID,
                            triggeredByUserSend: threadID == namingThreadID,
                            turnID: draftSnapshot.turnID,
                            diagnosticRunID: diagnosticRunID,
                            perMessageMCPServerIDs: draftSnapshot.perMessageMCPServerIDs
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    let cancellationReason = prepareToSendCancellationReason
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    prepareToSendCancellationReason = nil
                    if !(error is CancellationError) || cancellationReason == .userCancelled {
                        messageText = draftSnapshot.messageText
                        remoteVideoInputURLText = draftSnapshot.remoteVideoURLText
                        draftAttachments = draftSnapshot.attachments
                        draftQuotes = draftSnapshot.quotes
                    }
                    if !(error is CancellationError) {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }

        prepareToSendTask = task
    }

    // MARK: - Message Preparation

    func buildUserMessagePartsForThreads(
        threads: [ConversationModelThreadEntity],
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?
    ) async throws -> [ChatMessagePreparationSupport.ThreadPreparedUserMessage] {
        var preparedMessages: [ChatMessagePreparationSupport.ThreadPreparedUserMessage] = []
        preparedMessages.reserveCapacity(threads.count)

        for thread in threads {
            try Task.checkCancellation()
            let profile = try messagePreparationProfile(for: thread)
            let hasTextualPrompt =
                !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || quoteContents.contains {
                    !$0.quotedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            if profile.supportsMediaGenerationControl && !hasTextualPrompt {
                let mediaType = profile.supportsVideoGenerationControl ? "Video" : "Image"
                throw LLMError.invalidRequest(message: "\(mediaType) generation models require a text prompt. (\(profile.modelName))")
            }

            let parts = try await buildUserMessageParts(
                quoteContents: quoteContents,
                messageText: messageText,
                attachments: attachments,
                remoteVideoURL: remoteVideoURL,
                profile: profile
            )
            preparedMessages.append(ChatMessagePreparationSupport.ThreadPreparedUserMessage(threadID: profile.threadID, parts: parts))
        }

        return preparedMessages
    }

    func messagePreparationProfile(for thread: ConversationModelThreadEntity) throws -> ChatMessagePreparationSupport.MessagePreparationProfile {
        try ChatMessagePreparationSupport.messagePreparationProfile(
            for: thread,
            providers: providers,
            controls: controls,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode
        )
    }

    func providerType(forProviderID providerID: String) -> ProviderType? {
        ChatMessagePreparationSupport.providerType(forProviderID: providerID, providers: providers)
    }

    func buildUserMessageParts(
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: ChatMessagePreparationSupport.MessagePreparationProfile
    ) async throws -> [ContentPart] {
        try await ChatMessagePreparationSupport.buildUserMessageParts(
            quoteContents: quoteContents,
            messageText: messageText,
            attachments: attachments,
            remoteVideoURL: remoteVideoURL,
            profile: profile,
            preparedContentForPDF: { attachment, profile, mode, total, ordinal, mistral, mineru, deepseek, openRouter, firecrawl, r2Uploader in
                try await ChatMessagePreparationSupport.preparedContentForPDF(
                    attachment,
                    profile: profile,
                    requestedMode: mode,
                    totalPDFCount: total,
                    pdfOrdinal: ordinal,
                    mistralClient: mistral,
                    mineruClient: mineru,
                    deepSeekClient: deepseek,
                    openRouterClient: openRouter,
                    firecrawlClient: firecrawl,
                    r2Uploader: r2Uploader,
                    onStatusUpdate: { [self] status in
                        prepareToSendStatus = status
                    }
                )
            }
        )
    }

    func resolvedRemoteVideoInputURL(from raw: String) throws -> URL? {
        try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
            from: raw,
            supportsExplicitRemoteVideoURLInput: supportsExplicitRemoteVideoURLInput
        )
    }

    func makeConversationTitle(from userText: String) -> String {
        ChatMessagePreparationSupport.makeConversationTitle(from: userText)
    }

    // MARK: - MCP Tool Capability

    func threadSupportsMCPTools(
        providerType: ProviderType?,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType) else { return false }
        guard providerType != .codexAppServer else { return false }
        guard !(resolvedModelSettings?.capabilities.contains(.imageGeneration) == true
                || resolvedModelSettings?.capabilities.contains(.videoGeneration) == true) else {
            return false
        }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    func threadSupportsMCPTools(for thread: ConversationModelThreadEntity) -> Bool {
        let providerEntity = providers.first(where: { $0.id == thread.providerID })
        let providerTypeSnapshot = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) } ?? ProviderType(rawValue: thread.providerID)
        let threadControls = (try? JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)) ?? GenerationControls()
        let modelID = providerTypeSnapshot == .claudeManagedAgents
            ? ClaudeManagedAgentRuntime.resolvedRuntimeModelID(threadModelID: thread.modelID, controls: threadControls)
            : effectiveModelID(
                for: thread.modelID,
                providerEntity: providerEntity,
                providerType: providerTypeSnapshot
            )
        let modelInfoSnapshot = resolvedModelInfo(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let normalizedModelInfoSnapshot = modelInfoSnapshot.map {
            normalizedModelInfo($0, for: providerTypeSnapshot)
        }
        let resolvedModelSettingsSnapshot = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }
        return threadSupportsMCPTools(
            providerType: providerTypeSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot
        )
    }

    // MARK: - Start Streaming

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
            errorMessage = "Failed to load conversation settings: \(error.localizedDescription)"
            showingError = true
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
            errorMessage = "Failed to load provider configuration: \(error.localizedDescription)"
            showingError = true
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
            isAgentModeActive: isAgentModeActive,
            automaticContextCacheControls: { providerType, modelID, modelCapabilities in
                automaticContextCacheControls(
                    providerType: providerType,
                    modelID: modelID,
                    modelCapabilities: modelCapabilities
                )
            },
            sanitizeProviderSpecific: Self.sanitizeProviderSpecificForProvider,
            injectCodexThreadPersistence: { controls in
                injectCodexThreadPersistence(into: &controls, from: thread)
            },
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
            errorMessage = "Failed to load MCP server configs: \(error.localizedDescription)"
            showingError = true
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
                    rebuildMessageCaches()
                    autoOpenLatestArtifactIfNeeded(from: message, threadID: threadID)
                    try? modelContext.save()
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
                    rebuildMessageCaches()
                    try? modelContext.save()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            },
            persistCodexThreadState: { [self] state, localThreadID in
                persistCodexThreadState(state, forLocalThreadID: localThreadID)
            },
            persistClaudeManagedSessionState: { [self] state, localThreadID in
                persistClaudeManagedAgentSessionState(state, forLocalThreadID: localThreadID)
            },
            persistClaudeManagedPendingToolResults: { [self] results, localThreadID in
                persistClaudeManagedPendingCustomToolResults(results, forLocalThreadID: localThreadID)
            },
            appendCodexInteraction: { [self] request, localThreadID in
                pendingCodexInteractions.append(PendingCodexInteraction(localThreadID: localThreadID, request: request))
            },
            mergeSearchActivities: { [self] messageID, activities in
                mergeSearchActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            mergeAgentToolActivities: { [self] messageID, activities in
                mergeAgentToolActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            maybeAutoRename: { [self] provider, targetModelID, history, assistantMessage in
                await maybeAutoRenameConversation(
                    targetProvider: provider,
                    targetModelID: targetModelID,
                    history: history,
                    finalAssistantMessage: assistantMessage
                )
            },
            appendAgentApproval: { [self] request, localThreadID in
                pendingAgentApprovals.append(PendingAgentApproval(localThreadID: localThreadID, request: request))
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
                pendingCodexInteractions.removeAll { $0.localThreadID == sessionThreadID }
                pendingAgentApprovals.removeAll { $0.localThreadID == sessionThreadID }
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

    // MARK: - Agent Mode

    static func resolvedAgentModeControls(active: Bool) -> AgentModeControls? {
        guard active, AppPreferences.isPluginEnabled("agent_mode") else { return nil }
        let defaults = UserDefaults.standard
        let workingDir = defaults.string(forKey: AppPreferenceKeys.agentModeWorkingDirectory) ?? ""
        let customPrefixesJSON = defaults.string(forKey: AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) ?? "[]"
        let customPrefixes = (try? JSONDecoder().decode([String].self, from: Data(customPrefixesJSON.utf8))) ?? []
        let safePrefixes = AgentCommandAllowlist.resolvedSafePrefixes(defaults: defaults)
        let prefixes = safePrefixes + customPrefixes
        let timeout = defaults.object(forKey: AppPreferenceKeys.agentModeCommandTimeoutSeconds) as? Int ?? 120
        let autoApproveReads = defaults.object(forKey: AppPreferenceKeys.agentModeAutoApproveFileReads) as? Bool ?? true
        let bypassPermissions = defaults.object(forKey: AppPreferenceKeys.agentModeBypassPermissions) as? Bool ?? false
        let tools = AgentEnabledTools(
            shellExecute: defaults.object(forKey: AppPreferenceKeys.agentModeToolShell) as? Bool ?? true,
            fileRead: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileRead) as? Bool ?? true,
            fileWrite: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileWrite) as? Bool ?? true,
            fileEdit: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileEdit) as? Bool ?? true,
            globSearch: defaults.object(forKey: AppPreferenceKeys.agentModeToolGlob) as? Bool ?? true,
            grepSearch: defaults.object(forKey: AppPreferenceKeys.agentModeToolGrep) as? Bool ?? true
        )
        return AgentModeControls(
            enabled: true,
            workingDirectory: workingDir.isEmpty ? nil : workingDir,
            allowedCommandPrefixes: prefixes,
            autoApproveFileReads: autoApproveReads,
            bypassPermissions: bypassPermissions,
            enabledTools: tools,
            commandTimeoutSeconds: timeout,
            maxOutputBytes: 102_400
        )
    }

    // MARK: - Chat Naming

    var isChatNamingPluginEnabled: Bool {
        AppPreferences.isPluginEnabled("chat_naming")
    }

    var chatNamingMode: ChatNamingMode {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: AppPreferenceKeys.chatNamingMode) ?? ChatNamingMode.firstRoundFixed.rawValue
        return ChatNamingMode(rawValue: raw) ?? .firstRoundFixed
    }

    @MainActor
    func resolvedChatNamingTarget() -> (provider: ProviderConfig, modelID: String)? {
        guard isChatNamingPluginEnabled else { return nil }

        let defaults = UserDefaults.standard
        let providerID = (defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = (defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        guard let providerEntity = providers.first(where: { $0.id == providerID }),
              let provider = try? providerEntity.toDomain() else {
            return nil
        }

        let models = ChatNamingModelSupport.supportedModels(
            from: providerEntity.enabledModels,
            providerType: ProviderType(rawValue: providerEntity.typeRaw)
        )
        guard models.contains(where: { $0.id == modelID }),
              ChatNamingModelSupport.isSupported(providerConfig: provider, modelID: modelID) else {
            return nil
        }

        return (provider, modelID)
    }

    @MainActor
    func maybeAutoRenameConversation(
        targetProvider: ProviderConfig,
        targetModelID: String,
        history: [Message],
        finalAssistantMessage: Message
    ) async {
        guard let latestUser = history.last(where: { $0.role == .user }) else { return }

        if chatNamingMode == .firstRoundFixed {
            let current = conversationEntity.title
            if current != "New Chat" {
                return
            }
        }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: targetProvider,
                modelID: targetModelID,
                contextMessages: [latestUser, finalAssistantMessage],
                maxCharacters: 40
            )

            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else { return }
            conversationEntity.title = normalized
            try? modelContext.save()
        } catch {
            if chatNamingMode == .firstRoundFixed {
                if conversationEntity.title == "New Chat" {
                    conversationEntity.title = fallbackTitleFromMessage(latestUser)
                    try? modelContext.save()
                }
            }
        }
    }

    func fallbackTitleFromMessage(_ message: Message) -> String {
        ChatMessagePreparationSupport.fallbackTitleFromMessage(message)
    }

    // MARK: - Activity Merging

    @MainActor
    func mergeSearchActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [SearchActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        entity.searchActivitiesData = ChatMessageActivityMergeSupport.mergedSearchActivities(
            existingData: entity.searchActivitiesData,
            newActivities: newActivities
        )
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    func mergeAgentToolActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [CodexToolActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        entity.agentToolActivitiesData = ChatMessageActivityMergeSupport.mergedAgentToolActivities(
            existingData: entity.agentToolActivitiesData,
            newActivities: newActivities
        )
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }
}
