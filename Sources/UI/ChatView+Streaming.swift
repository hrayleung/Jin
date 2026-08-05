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

        isPreparingToSend = true
        prepareToSendStatus = nil
        prepareToSendCancellationReason = nil

        // ── Fast path: no PDF OCR ──────────────────────────────────────────
        // CRITICAL ORDER (why "blank after Enter" kept surviving earlier fixes):
        //
        // `ComposerTextStore` is intentionally isolated from ChatView's body so
        // typing stays cheap. Clearing it therefore can repaint the composer
        // EMPTY *before* ChatView re-evaluates the timeline. If we clear draft
        // first and only then append the render-cache row, the user sees a
        // blank gap — even when both mutations are "synchronous" on the main
        // actor (separate Observation invalidation trees / AppKit text views
        // apply immediately).
        //
        // Order must be: paint bubble → then clear composer → then stream.
        // Also skip JSON encode→decode for the render item (domain path).
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
                // 1) Paint first — bubble lands in renderCache.
                commitPreparedUserTurn(
                    parts: parts,
                    draft: draftSnapshot,
                    diagnosticRunID: diagnosticRunID,
                    persistToDisk: false
                )
                // 2) Clear draft only AFTER paint is in the cache. Clearing
                //    ComposerTextStore first can repaint an empty field with no
                //    timeline invalidation (store is isolated from ChatView
                //    body) — that is the blank gap. Paint-then-clear in the
                //    same turn batches both Observation trees into one frame:
                //    bubble present + field empty together.
                clearComposerDraftAfterSend()
                let perMessageIDs = draftSnapshot.perMessageMCPServerIDs
                // Assign to prepareToSendTask so Stop during the yield window
                // cancels streaming without undoing the painted turn.
                let task = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else {
                        self.finishPrepareToSendChrome()
                        return
                    }
                    try? self.modelContext.save()
                    guard !Task.isCancelled else {
                        self.finishPrepareToSendChrome()
                        return
                    }
                    self.startStreamingResponse(
                        triggeredByUserSend: true,
                        diagnosticRunID: diagnosticRunID,
                        perMessageMCPServerIDs: perMessageIDs
                    )
                    self.finishPrepareToSendChrome()
                }
                prepareToSendTask = task
            } catch {
                // Paint never landed — draft was never cleared.
                restoreDraftAfterFailedPrepare(
                    draft: draftSnapshot,
                    error: error,
                    wasCancellation: false
                )
            }
            return
        }

        // ── Slow path: PDF (or other) async preparation ────────────────────
        // Long-running prepare: clear the composer immediately and show status.
        // A multi-second OCR wait with the draft still sitting in the field
        // feels stuck; blank-until-ready is acceptable only for this path.
        clearComposerDraftAfterSend()
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
                guard !Task.isCancelled else {
                    // Parts already painted; cancel means skip stream only.
                    await MainActor.run { self.finishPrepareToSendChrome() }
                    return
                }
                await MainActor.run {
                    guard !Task.isCancelled else {
                        self.finishPrepareToSendChrome()
                        return
                    }
                    self.startStreamingResponse(
                        triggeredByUserSend: true,
                        diagnosticRunID: diagnosticRunID,
                        perMessageMCPServerIDs: draftSnapshot.perMessageMCPServerIDs
                    )
                    self.finishPrepareToSendChrome()
                }
            } catch {
                // Cancellation here is only from pre-commit prepare (PDF OCR
                // etc.). Post-commit cancel is handled above after yield and
                // leaves the painted user turn in place.
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

    /// Clears composer chrome after the user bubble has been painted into the
    /// render cache (fast path), or immediately when a long prepare is about
    /// to start (PDF path). See send-path ordering notes above.
    @MainActor
    private func clearComposerDraftAfterSend() {
        messageText = ""
        remoteVideoInputURLText = ""
        composerTextContentHeight = 36
        draftAttachments = []
        draftQuotes = []
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
