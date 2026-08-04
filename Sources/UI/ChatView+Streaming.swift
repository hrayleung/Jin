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
            presentError("Please choose a model before sending.")
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
            presentError(error.localizedDescription)
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

        // ── Fast path: no PDF OCR ──────────────────────────────────────────
        // Build parts + paint the user bubble on THIS runloop turn (same as
        // the keypress). Hopping through `Task { await build… }` always
        // suspends once even when the builder never awaits, which left a
        // multi-frame blank after Enter. Streaming setup is deferred to the
        // next turn so `startStreamingResponse`'s snapshot work cannot block
        // the first paint of the user row.
        let needsAsyncPrepare = ChatMessagePreparationSupport.requiresAsyncPreparation(
            attachments: draftSnapshot.attachments
        )
        if !needsAsyncPrepare {
            do {
                let parts = try buildUserMessagePartsSync(
                    quoteContents: draftSnapshot.quoteContents,
                    messageText: draftSnapshot.messageText,
                    attachments: draftSnapshot.attachments,
                    remoteVideoURL: remoteVideoURLSnapshot
                )
                // Paint the user bubble on this keypress turn — skip SwiftData
                // save here so a disk flush cannot delay the first frame.
                commitPreparedUserTurn(
                    parts: parts,
                    draft: draftSnapshot,
                    diagnosticRunID: diagnosticRunID,
                    persistToDisk: false
                )
                let perMessageIDs = draftSnapshot.perMessageMCPServerIDs
                // Keep isPreparingToSend true until streaming arms so the send
                // button cannot flip back to Send for one frame (double-send).
                // Yield first so the user bubble paints before save + snapshot work.
                Task { @MainActor in
                    await Task.yield()
                    try? self.modelContext.save()
                    self.startStreamingResponse(
                        triggeredByUserSend: true,
                        diagnosticRunID: diagnosticRunID,
                        perMessageMCPServerIDs: perMessageIDs
                    )
                    self.finishPrepareToSendChrome()
                }
            } catch {
                restoreDraftAfterFailedPrepare(
                    draft: draftSnapshot,
                    error: error,
                    wasCancellation: false
                )
            }
            return
        }

        // ── Slow path: PDF (or other) async preparation ────────────────────
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
                    self.commitPreparedUserTurn(
                        parts: parts,
                        draft: draftSnapshot,
                        diagnosticRunID: diagnosticRunID
                    )
                }
                // Yield so the user row paints before streaming setup.
                await Task.yield()
                await MainActor.run {
                    self.startStreamingResponse(
                        triggeredByUserSend: true,
                        diagnosticRunID: diagnosticRunID,
                        perMessageMCPServerIDs: draftSnapshot.perMessageMCPServerIDs
                    )
                    self.finishPrepareToSendChrome()
                }
            } catch {
                await MainActor.run {
                    self.restoreDraftAfterFailedPrepare(
                        draft: draftSnapshot,
                        error: error,
                        wasCancellation: error is CancellationError
                    )
                }
            }
        }

        prepareToSendTask = task
    }

    /// Append the user turn to SwiftData + render cache so the bubble is in
    /// the table model. Does **not** start streaming — callers schedule that
    /// after a yield so the user row is free to paint first.
    ///
    /// - Parameter persistToDisk: when false (fast path), skip `modelContext.save()`
    ///   so a disk flush cannot delay the first paint; the caller must save
    ///   before/with streaming setup.
    @MainActor
    private func commitPreparedUserTurn(
        parts: [ContentPart],
        draft: ChatSendDraftSnapshot,
        diagnosticRunID: String,
        persistToDisk: Bool = true
    ) {
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
            draft: draft,
            toolCapable: threadSupportsMCPTools(
                providerType: providerType,
                resolvedModelSettings: resolvedModelSettings
            ),
            conversationEntity: conversationEntity,
            isChatNamingPluginEnabled: isChatNamingPluginEnabled,
            persistConversationIfNeeded: onPersistConversationIfNeeded,
            makeConversationTitle: makeConversationTitle(from:),
            applyRenderCaches: applyAppendedUserTurnToRenderCaches
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

        if persistToDisk {
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

        // Leave isPreparingToSend true until streaming arms (see
        // finishPrepareToSendChrome) so isBusy stays continuous Send→Stop.
        prepareToSendStatus = nil
        perMessageMCPServerIDs = []
    }

    @MainActor
    private func finishPrepareToSendChrome() {
        isPreparingToSend = false
        prepareToSendStatus = nil
        prepareToSendTask = nil
        prepareToSendCancellationReason = nil
    }

    @MainActor
    private func restoreDraftAfterFailedPrepare(
        draft: ChatSendDraftSnapshot,
        error: Error,
        wasCancellation: Bool
    ) {
        let cancellationReason = prepareToSendCancellationReason
        finishPrepareToSendChrome()
        if !wasCancellation || cancellationReason == .userCancelled {
            messageText = draft.messageText
            remoteVideoInputURLText = draft.remoteVideoURLText
            draftAttachments = draft.attachments
            draftQuotes = draft.quotes
        }
        if !wasCancellation {
            presentError(error.localizedDescription)
        }
    }
}
