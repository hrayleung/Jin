import SwiftData
import Foundation

// MARK: - Send

extension ChatView {

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
}
