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

        let messageTextSnapshot = trimmedMessageText
        let remoteVideoURLTextSnapshot = trimmedRemoteVideoInputURLText
        let attachmentsSnapshot = draftAttachments
        let selectedPerMessageMCPServers = eligibleMCPServers.filter { perMessageMCPServerIDs.contains($0.id) }
        let perMessageMCPIDsSnapshot = selectedPerMessageMCPServers.map(\.id).sorted()
        let perMessageMCPNamesSnapshot = selectedPerMessageMCPServers.map(\.name).sorted()
        let perMessageMCPIDsData: Data? = perMessageMCPIDsSnapshot.isEmpty ? nil : try? JSONEncoder().encode(perMessageMCPIDsSnapshot)
        let perMessageMCPSnapshot = Set(perMessageMCPIDsSnapshot)
        let askedAt = Date()
        let turnID = UUID()

        let remoteVideoURLSnapshot: URL?
        do {
            remoteVideoURLSnapshot = try resolvedRemoteVideoInputURL(from: remoteVideoURLTextSnapshot)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        messageText = ""
        remoteVideoInputURLText = ""
        composerTextContentHeight = 36
        draftAttachments = []

        isPreparingToSend = true
        prepareToSendStatus = nil
        prepareToSendCancellationReason = nil

        let task = Task {
            do {
                let preparedMessages = try await buildUserMessagePartsForThreads(
                    threads: targetThreads,
                    messageText: messageTextSnapshot,
                    attachments: attachmentsSnapshot,
                    remoteVideoURL: remoteVideoURLSnapshot
                )

                await MainActor.run {
                    if conversationEntity.messages.isEmpty {
                        onPersistConversationIfNeeded()
                    }

                    let toolCapableThreadIDs = Set(targetThreads.compactMap { threadSupportsMCPTools(for: $0) ? $0.id : nil })
                    for prepared in preparedMessages {
                        let message = Message(
                            role: .user,
                            content: prepared.parts,
                            timestamp: askedAt,
                            perMessageMCPServerNames: toolCapableThreadIDs.contains(prepared.threadID) ? perMessageMCPNamesSnapshot : nil
                        )
                        guard let messageEntity = try? MessageEntity.fromDomain(message) else { continue }
                        if toolCapableThreadIDs.contains(prepared.threadID) {
                            messageEntity.perMessageMCPServerIDsData = perMessageMCPIDsData
                        }
                        messageEntity.contextThreadID = prepared.threadID
                        messageEntity.turnID = turnID
                        messageEntity.conversation = conversationEntity
                        conversationEntity.messages.append(messageEntity)
                    }

                    if conversationEntity.title == "New Chat", !isChatNamingPluginEnabled {
                        if !messageTextSnapshot.isEmpty {
                            conversationEntity.title = makeConversationTitle(from: messageTextSnapshot)
                        } else if let firstAttachment = attachmentsSnapshot.first {
                            conversationEntity.title = makeConversationTitle(from: (firstAttachment.filename as NSString).deletingPathExtension)
                        }
                    }
                    conversationEntity.updatedAt = askedAt
                    rebuildMessageCaches()
                    try? modelContext.save()
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
                            turnID: turnID,
                            perMessageMCPServerIDs: perMessageMCPSnapshot
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
                        messageText = messageTextSnapshot
                        remoteVideoInputURLText = remoteVideoURLTextSnapshot
                        draftAttachments = attachmentsSnapshot
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
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?
    ) async throws -> [ChatMessagePreparationSupport.ThreadPreparedUserMessage] {
        var preparedMessages: [ChatMessagePreparationSupport.ThreadPreparedUserMessage] = []
        preparedMessages.reserveCapacity(threads.count)

        for thread in threads {
            try Task.checkCancellation()
            let profile = try messagePreparationProfile(for: thread)
            if profile.supportsMediaGenerationControl && messageText.isEmpty {
                let mediaType = profile.supportsVideoGenerationControl ? "Video" : "Image"
                throw LLMError.invalidRequest(message: "\(mediaType) generation models require a text prompt. (\(profile.modelName))")
            }

            let parts = try await buildUserMessageParts(
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
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode
        )
    }

    func providerType(forProviderID providerID: String) -> ProviderType? {
        ChatMessagePreparationSupport.providerType(forProviderID: providerID, providers: providers)
    }

    func buildUserMessageParts(
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: ChatMessagePreparationSupport.MessagePreparationProfile
    ) async throws -> [ContentPart] {
        try await ChatMessagePreparationSupport.buildUserMessageParts(
            messageText: messageText,
            attachments: attachments,
            remoteVideoURL: remoteVideoURL,
            profile: profile,
            preparedContentForPDF: { attachment, profile, mode, total, ordinal, mistral, deepseek in
                try await ChatMessagePreparationSupport.preparedContentForPDF(
                    attachment,
                    profile: profile,
                    requestedMode: mode,
                    totalPDFCount: total,
                    pdfOrdinal: ordinal,
                    mistralClient: mistral,
                    deepSeekClient: deepseek,
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
        let modelID = effectiveModelID(
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
        perMessageMCPServerIDs: Set<String> = []
    ) {
        let conversationID = conversationEntity.id
        guard !streamingStore.isStreaming(conversationID: conversationID, threadID: threadID) else { return }

        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        let providerID = thread.providerID
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerTypeSnapshot = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) } ?? ProviderType(rawValue: providerID)
        let modelID = effectiveModelID(
            for: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        migrateThreadModelIDIfNeeded(thread, resolvedModelID: modelID)
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
        let modelNameSnapshot = normalizedModelInfoSnapshot?.name ?? modelID
        let streamingState = streamingStore.beginSession(
            conversationID: conversationID,
            threadID: threadID,
            modelLabel: modelNameSnapshot
        )
        streamingState.reset()

        let providerConfig: ProviderConfig?
        if let entity = providerEntity {
            do {
                providerConfig = try entity.toDomain()
            } catch {
                errorMessage = "Failed to load provider configuration: \(error.localizedDescription)"
                showingError = true
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                return
            }
        } else {
            providerConfig = nil
        }
        let messageSnapshots = conversationEntity.messages.map { PersistedMessageSnapshot($0) }
        let assistant = conversationEntity.assistant
        let systemPrompt = resolvedSystemPrompt(
            conversationSystemPrompt: conversationEntity.systemPrompt,
            assistant: assistant
        )
        var controlsToUse: GenerationControls
        do {
            controlsToUse = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        } catch {
            errorMessage = "Failed to load conversation settings: \(error.localizedDescription)"
            showingError = true
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            return
        }
        controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: controlsToUse,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens,
            modelMaxOutputTokens: resolvedModelSettingsSnapshot?.maxOutputTokens
        )
        controlsToUse.contextCache = automaticContextCacheControls(
            providerType: providerTypeSnapshot,
            modelID: modelID,
            modelCapabilities: resolvedModelSettingsSnapshot?.capabilities
        )
        Self.sanitizeProviderSpecificForProvider(providerTypeSnapshot, controls: &controlsToUse)
        injectCodexThreadPersistence(into: &controlsToUse, from: thread)
        controlsToUse.agentMode = Self.resolvedAgentModeControls(active: isAgentModeActive)

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let maxHistoryMessages = assistant?.maxHistoryMessages
        let modelContextWindow = resolvedModelSettingsSnapshot?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let threadSupportsPerMessageMCP = threadSupportsMCPTools(
            providerType: providerTypeSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot
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
        let supportsBuiltinSearchPlugin = (resolvedModelSettingsSnapshot?.capabilities.contains(.toolCalling) == true)
            && webSearchPluginEnabled
            && webSearchPluginConfigured
        let supportsNativeSearch = ModelCapabilityRegistry.supportsWebSearch(for: providerTypeSnapshot, modelID: modelID)
        let shouldOfferBuiltinSearch = supportsBuiltinSearchPlugin
            && (!supportsNativeSearch || controlsToUse.searchPlugin?.preferJinSearch == true)
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
            providerID: providerID,
            providerConfig: providerConfig,
            providerType: providerTypeSnapshot,
            modelID: modelID,
            modelNameSnapshot: modelNameSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot,
            messageSnapshots: messageSnapshots,
            systemPrompt: systemPrompt,
            controlsToUse: controlsToUse,
            shouldTruncateMessages: shouldTruncateMessages,
            maxHistoryMessages: maxHistoryMessages,
            modelContextWindow: modelContextWindow,
            reservedOutputTokens: reservedOutputTokens,
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

        let models = providerEntity.enabledModels
        guard models.contains(where: { $0.id == modelID }) else { return nil }

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

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let existingActivities: [SearchActivity]
        if let data = entity.searchActivitiesData,
           let decoded = try? decoder.decode([SearchActivity].self, from: data) {
            existingActivities = decoded
        } else {
            existingActivities = []
        }

        var byID: OrderedDictionary<String, SearchActivity> = [:]

        for activity in existingActivities {
            byID[activity.id] = activity
        }

        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                byID[activity.id] = activity
            }
        }

        let mergedActivities = Array(byID.values)
        entity.searchActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
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

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let existingActivities: [CodexToolActivity]
        if let data = entity.agentToolActivitiesData,
           let decoded = try? decoder.decode([CodexToolActivity].self, from: data) {
            existingActivities = decoded
        } else {
            existingActivities = []
        }

        var byID: OrderedDictionary<String, CodexToolActivity> = [:]
        for activity in existingActivities {
            byID[activity.id] = activity
        }
        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                byID[activity.id] = activity
            }
        }

        let mergedActivities = Array(byID.values)
        entity.agentToolActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }
}
