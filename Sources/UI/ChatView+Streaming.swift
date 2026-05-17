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

        guard !conversationEntity.providerID.isEmpty, !conversationEntity.modelID.isEmpty else {
            errorMessage = "Please choose a model before sending."
            showingError = true
            return
        }

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
                let parts = try await buildUserMessageParts(
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
                            "messageCountBeforePersist": String(conversationEntity.messages.count)
                        ]
                    )
                    // #endregion

                    let rebuildStartedAt = ProcessInfo.processInfo.systemUptime
                    ChatUserTurnPersistence.appendPreparedUserMessage(
                        parts: parts,
                        draft: draftSnapshot,
                        toolCapable: threadSupportsMCPTools(
                            providerType: providerType,
                            resolvedModelSettings: resolvedModelSettings
                        ),
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
                    startStreamingResponse(
                        triggeredByUserSend: true,
                        diagnosticRunID: diagnosticRunID,
                        perMessageMCPServerIDs: draftSnapshot.perMessageMCPServerIDs
                    )
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
