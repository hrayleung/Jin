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
        // Never touch `conversationEntity.messages` here — faulting the full
        // relationship on Enter is a common "wait a beat before the bubble"
        // stall on long chats. Use the denormalized / cache counters only.
        ChatDiagnosticLogger.log(
            runId: diagnosticRunID,
            hypothesisId: "H4",
            message: "chat_send_entry",
            data: [
                "conversationID": conversationEntity.id.uuidString,
                "messageCount": String(conversationEntity.resolvedMessageCount),
                "cachedMessageCount": String(renderCache.cachedTotalMessageCount),
                "isStreaming": String(isStreaming),
                "isPreparingToSend": String(isPreparingToSend),
                "isImportingDropAttachments": String(isImportingDropAttachments),
                "canSendDraft": String(canSendDraft)
            ]
        )
        // #endregion
        // Stop: cancel in-flight generation and/or the prepare window. With
        // early-armed streaming placeholders, both flags can be true at once —
        // cancel the prepare task AND the store so we never resume into a new
        // startStreamingResponse after the user hit Stop.
        if isStreaming || isPreparingToSend {
            if isPreparingToSend {
                prepareToSendCancellationReason = .userCancelled
                prepareToSendTask?.cancel()
            }
            streamingStore.cancel(conversationID: conversationEntity.id)
            return
        }

        guard !isImportingDropAttachments else { return }
        guard canSendDraft else { return }
        endEditingUI()

        guard !conversationEntity.providerID.isEmpty, !conversationEntity.modelID.isEmpty else {
            presentError("Please choose a model before sending.")
            return
        }

        // Snapshot draft with the lightest work possible. MCP name lookup is
        // only needed for the painted badge; keep the filter tight.
        let selectedPerMessageMCPServers: [(id: String, name: String)]
        if perMessageMCPServerIDs.isEmpty {
            selectedPerMessageMCPServers = []
        } else {
            selectedPerMessageMCPServers = eligibleMCPServers
                .filter { perMessageMCPServerIDs.contains($0.id) }
                .map { (id: $0.id, name: $0.name) }
        }
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

        prepareToSendStatus = nil
        prepareToSendCancellationReason = nil

        // ── Fast path: no PDF OCR ──────────────────────────────────────────
        // CRITICAL ORDER (why "blank after Enter" / white flash kept surviving):
        //
        // 1. `ComposerTextStore` is isolated from ChatView body (typing perf).
        //    Clearing it first can repaint an empty field with no timeline
        //    invalidation → blank gap.
        // 2. `isPreparingToSend` is ChatView `@State` — setting it *before*
        //    paint invalidates the whole chat tree without a bubble yet.
        // 3. When history exceeds `messageRenderLimit` (24), a send *slides*
        //    the window (drop head + insert tail = batchDiff). That is the
        //    intermittent full-stage white flash on long chats. Grow the
        //    limit while pinned so send is pure appendTail instead.
        // 4. Heavy setup (SwiftData save, provider resolve, full-history
        //    snapshot) must NOT run on this turn — it steals the first paint
        //    and makes Enter feel laggy. Paint → return → yield → heavy work.
        //
        // Order: expand window → paint bubble → arm Generating → busy flag →
        //        clear composer → return; stream after paint yields.
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
                // Avoid long-chat window slide on this send (see expand helper).
                // +1 user turn +1 streaming placeholder so the window does not
                // slide when the Generating row appears on the same send.
                expandRenderWindowForPinnedSendIfNeeded(additionalMessages: 1)
                // 1) Paint first — bubble lands in renderCache.
                commitPreparedUserTurn(
                    parts: parts,
                    draft: draftSnapshot,
                    diagnosticRunID: diagnosticRunID,
                    persistToDisk: false
                )
                // 1b) Arm streaming session immediately so the Generating
                // placeholder paints in the same turn as the user bubble.
                armStreamingPlaceholderSession(diagnosticRunID: diagnosticRunID)
                // 2) Busy chrome after paint (Stop button) — not before.
                isPreparingToSend = true
                // 3) Clear draft only AFTER paint is in the cache.
                clearComposerDraftAfterSend()
                let perMessageIDs = draftSnapshot.perMessageMCPServerIDs
                // Assign to prepareToSendTask so Stop during the yield window
                // cancels streaming without undoing the painted turn.
                let task = Task { @MainActor in
                    // First yield: let SwiftUI commit the user bubble +
                    // Generating row before any disk / provider work.
                    await Task.yield()
                    // Always persist the painted user turn before any cancel
                    // exit or network start — commit used persistToDisk: false
                    // so Stop in the yield window would otherwise leave the
                    // message only in-memory and lose it on relaunch.
                    do {
                        try self.modelContext.save()
                    } catch {
                        self.streamingStore.cancel(conversationID: self.conversationEntity.id)
                        self.finishPrepareToSendChrome()
                        self.presentError("Failed to save chat: \(error.localizedDescription)")
                        return
                    }
                    guard !Task.isCancelled else {
                        self.streamingStore.cancel(conversationID: self.conversationEntity.id)
                        self.finishPrepareToSendChrome()
                        return
                    }
                    // Second yield: save can be expensive; give layout another
                    // chance before startStreamingResponse resolves providers
                    // and (on cache miss) walks full history.
                    await Task.yield()
                    guard !Task.isCancelled else {
                        self.streamingStore.cancel(conversationID: self.conversationEntity.id)
                        self.finishPrepareToSendChrome()
                        return
                    }
                    self.expandRenderWindowForPinnedSendIfNeeded(additionalMessages: 0)
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
                isPreparingToSend = false
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
        isPreparingToSend = true
        expandRenderWindowForPinnedSendIfNeeded(additionalMessages: 1)
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
                    // Arm Generating immediately after the user bubble so a
                    // multi-second OCR wait is not followed by another blank
                    // gap while startStreamingResponse resolves providers.
                    self.armStreamingPlaceholderSession(diagnosticRunID: diagnosticRunID)
                }
                // Yield so the user + streaming rows paint before network setup.
                await Task.yield()
                guard !Task.isCancelled else {
                    // Parts already painted; cancel means skip stream only.
                    await MainActor.run {
                        self.streamingStore.cancel(conversationID: self.conversationEntity.id)
                        self.finishPrepareToSendChrome()
                    }
                    return
                }
                await MainActor.run {
                    guard !Task.isCancelled else {
                        self.streamingStore.cancel(conversationID: self.conversationEntity.id)
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
                "messageCountBeforePersist": String(conversationEntity.resolvedMessageCount)
            ]
        )
        // #endregion

        // SwiftData count/updatedAt observers would fire a parallel
        // rebuildMessageCachesIfNeeded during the append — racing the fast
        // path and often forcing a full cell reconfigure (white flash).
        defersObservedMessageCacheRebuild = true
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
        // Keep the defer armed until the next turn so the observer that
        // already queued for this mutation still no-ops; clear on the next
        // main-queue pass after paint has been applied.
        DispatchQueue.main.async {
            self.defersObservedMessageCacheRebuild = false
        }
        let rebuildDurationMs = Int((ProcessInfo.processInfo.systemUptime - rebuildStartedAt) * 1000)

        // #region agent log
        ChatDiagnosticLogger.log(
            runId: diagnosticRunID,
            hypothesisId: "H1",
            message: "chat_persist_rebuild_complete",
            data: [
                "conversationID": conversationEntity.id.uuidString,
                "messageCountAfterAppend": String(conversationEntity.resolvedMessageCount),
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
                    "messageCountAfterSave": String(conversationEntity.resolvedMessageCount),
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

    /// Creates an idle streaming session so `StreamingMessageView` can paint
    /// the Generating placeholder immediately after the user turn. Safe to
    /// call when a session already exists (beginSession reuses it). The real
    /// network task is attached later by `startStreamingResponse`.
    @MainActor
    private func armStreamingPlaceholderSession(diagnosticRunID: String) {
        let conversationID = conversationEntity.id
        // Do not clobber an in-flight generation.
        guard !streamingStore.hasActiveStreamingTask(conversationID: conversationID) else { return }
        let provisionalModelID = conversationEntity.modelID.trimmedNonEmpty
        let state = streamingStore.beginSession(
            conversationID: conversationID,
            modelLabel: streamingModelLabel ?? provisionalModelID,
            modelID: provisionalModelID
        )
        state.debugContext = StreamingDebugContext(
            conversationID: conversationID,
            diagnosticRunID: diagnosticRunID
        )
        // Fresh idle chrome — never carry leftovers from a prior turn.
        state.reset()
        // Ensure the streaming row identity has room in the suffix window.
        expandRenderWindowForPinnedSendIfNeeded(additionalMessages: 0)
    }

    /// While pinned to bottom, grow `messageRenderLimit` so an outgoing send
    /// does **not** slide the suffix window (drop oldest visible id + insert
    /// newest). That slide is `batchDiff` and is the intermittent full-stage
    /// white flash on long conversations. Recycling still bounds live cells.
    @MainActor
    private func expandRenderWindowForPinnedSendIfNeeded(additionalMessages: Int) {
        guard isPinnedToBottom else { return }
        // Projected domain message count after this send (user turn).
        let projected = max(
            renderCache.cachedTotalMessageCount,
            conversationEntity.messages.count
        ) + max(0, additionalMessages)
        // +1 spare for the streaming placeholder row identity in the table.
        let needed = projected + 1
        if needed > messageRenderLimit {
            messageRenderLimit = needed
        }
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
