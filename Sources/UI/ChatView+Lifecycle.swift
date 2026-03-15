import Collections
import SwiftUI
import SwiftData
import AppKit

// MARK: - Lifecycle & Drop Handling

extension ChatView {

    func handleChatAppear() {
        isComposerFocused = true
        installWKWebViewDropForwarder()
        // loadControlsFromConversation internally calls ensureModelThreadsInitializedIfNeeded
        // and syncActiveThreadSelection, so calling them separately is redundant and causes
        // extra render cycles that make the header flicker.
        loadControlsFromConversation()
        rebuildMessageCaches()
        syncArtifactSelectionForActiveThread()
    }

    func handleConversationSwitch() {
        // Switching chats: reset ALL transient per-chat state, clear the
        // displayed messages immediately so the switch feels instant, then
        // rebuild caches on the next run-loop tick.

        // Editing / composer
        cancelEditingUserMessage()
        speechToTextManager.cancelAndCleanup()
        messageText = ""
        draftAttachments = []
        dropAttachmentImportInFlightCount = 0
        composerTextContentHeight = 36
        remoteVideoInputURLText = ""
        isExpandedComposerPresented = false
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
        perMessageMCPServerIDs = []

        // Prepare-to-send
        prepareToSendCancellationReason = .conversationSwitch
        prepareToSendTask?.cancel()
        isPreparingToSend = false
        prepareToSendStatus = nil
        prepareToSendTask = nil

        // Popovers / sheets / alerts
        isModelPickerPresented = false
        isAddModelPickerPresented = false
        showingThinkingBudgetSheet = false
        showingCodeExecutionSheet = false
        showingContextCacheSheet = false
        showingAnthropicWebSearchSheet = false
        showingImageGenerationSheet = false
        showingCodexSessionSettingsSheet = false
        showingGoogleMapsSheet = false
        googleMapsDraft = GoogleMapsControls()
        googleMapsLatitudeDraft = ""
        googleMapsLongitudeDraft = ""
        googleMapsLanguageCodeDraft = ""
        googleMapsDraftError = nil
        showingError = false
        errorMessage = nil

        // Codex
        pendingCodexInteractions = []

        // Agent
        pendingAgentApprovals = []

        // Scroll / pagination
        messageRenderLimit = Self.initialMessageRenderLimit
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true

        // Artifacts
        isArtifactPaneVisible = false
        selectedArtifactIDByThreadID = [:]
        selectedArtifactVersionByThreadID = [:]

        // Cancel any pending debounced rebuild from the previous conversation.
        updatedAtDebounceTask?.cancel()
        updatedAtDebounceTask = nil
        cancelRenderContextBuild()

        // Clear caches synchronously so stale content is never shown, then
        // load controls (lightweight) so the header reflects the new chat.
        cachedVisibleMessages = []
        cachedMessageEntitiesByID = [:]
        cachedToolResultsByCallID = [:]
        cachedArtifactCatalog = .empty
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = 0
        lastCacheRebuildUpdatedAt = .distantPast

        // loadControlsFromConversation internally calls ensureModelThreadsInitializedIfNeeded
        // and syncActiveThreadSelection, so calling them separately is redundant.
        loadControlsFromConversation()

        // Defer the heavy rebuild so SwiftUI can commit the state reset above
        // (clears the view) before we block the main actor with JSON decoding.
        let targetConversationID = conversationEntity.id
        Task { @MainActor in
            guard conversationEntity.id == targetConversationID else { return }
            rebuildMessageCaches()
            syncArtifactSelectionForActiveThread()
        }
    }

    func handleAttachmentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importAttachments(from: urls) }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Install a static drop forwarder on MarkdownWKWebView so files
    /// dropped directly onto rendered markdown messages are routed to the
    /// same attachment pipeline used by the SwiftUI `.onDrop` handler.
    func installWKWebViewDropForwarder() {
        let coordinator = FileDropCaptureView.Coordinator(
            isDropTargeted: $isFullPageDropTargeted,
            onDropFileURLs: handleDroppedFileURLs,
            onDropImages: handleDroppedImages,
            onDropTextChunks: handleDroppedTextChunks
        )
        dropForwarderRef.onDragTargetChanged = { isTargeted in coordinator.setDropTargeted(isTargeted) }
        dropForwarderRef.onPerformDrop = { draggingInfo in coordinator.performDrop(draggingInfo) }
    }

    // MARK: - Drop Handling

    func handleDroppedFileURLs(_ urls: [URL]) -> Bool {
        var uniqueURLs = OrderedSet<URL>()
        for url in urls {
            uniqueURLs.append(url)
        }
        guard !uniqueURLs.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        Task { await importAttachments(from: Array(uniqueURLs)) }
        return true
    }

    func handleDroppedImages(_ images: [NSImage]) -> Bool {
        guard !images.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        var urls: [URL] = []
        var errors: [String] = []

        for image in images {
            guard let url = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                errors.append("Failed to read dropped image.")
                continue
            }
            urls.append(url)
        }

        if !urls.isEmpty {
            Task { await importAttachments(from: urls) }
        }

        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
            showingError = true
        }

        return true
    }

    func handleDroppedTextChunks(_ textChunks: [String]) -> Bool {
        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to drop text."
            showingError = true
            return true
        }
        return appendTextChunksToComposer(textChunks)
    }

    @discardableResult
    func appendTextChunksToComposer(_ textChunks: [String]) -> Bool {
        guard let result = ChatDropHandlingSupport.appendTextChunksToComposer(textChunks, currentText: messageText) else {
            return false
        }
        messageText = result
        return true
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        isFullPageDropTargeted = false

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        let dropConversationID = conversationEntity.id

        let didSchedule = ChatDropHandlingSupport.processDropProviders(providers) { [self] result in
            Task { @MainActor in
                guard conversationEntity.id == dropConversationID else { return }
                guard !isBusy else { return }

                if !result.textChunks.isEmpty {
                    appendTextChunksToComposer(result.textChunks)
                }

                var allErrors = result.errors

                if !result.fileURLs.isEmpty {
                    let maxAttachments = AttachmentConstants.maxDraftAttachments
                    let attachmentCountAtDrop = draftAttachments.count
                    dropAttachmentImportInFlightCount += 1
                    defer {
                        if conversationEntity.id == dropConversationID {
                            dropAttachmentImportInFlightCount = max(0, dropAttachmentImportInFlightCount - 1)
                        }
                    }
                    let (newAttachments, importErrors) = await ChatDropHandlingSupport.importAttachments(
                        from: result.fileURLs,
                        currentAttachmentCount: attachmentCountAtDrop,
                        maxAttachments: maxAttachments
                    )

                    guard conversationEntity.id == dropConversationID else { return }
                    guard !isBusy else { return }

                    allErrors.append(contentsOf: importErrors)

                    if !newAttachments.isEmpty {
                        let remainingSlots = max(0, maxAttachments - draftAttachments.count)
                        let limitMessage = "You can attach up to \(maxAttachments) files per message."

                        if remainingSlots <= 0 {
                            if !allErrors.contains(limitMessage) {
                                allErrors.append(limitMessage)
                            }
                        } else {
                            let attachmentsToAppend = newAttachments.prefix(remainingSlots)
                            if attachmentsToAppend.count < newAttachments.count, !allErrors.contains(limitMessage) {
                                allErrors.append(limitMessage)
                            }
                            draftAttachments.append(contentsOf: attachmentsToAppend)
                        }
                    }
                }

                guard conversationEntity.id == dropConversationID else { return }
                guard !isBusy else { return }

                if !allErrors.isEmpty {
                    errorMessage = allErrors.joined(separator: "\n")
                    showingError = true
                }
            }
        }

        return didSchedule
    }

    func importAttachments(from urls: [URL]) async {
        guard !urls.isEmpty, !isStreaming else { return }

        let (newAttachments, errors) = await ChatDropHandlingSupport.importAttachments(
            from: urls,
            currentAttachmentCount: draftAttachments.count,
            maxAttachments: AttachmentConstants.maxDraftAttachments
        )

        await MainActor.run {
            if !newAttachments.isEmpty {
                draftAttachments.append(contentsOf: newAttachments)
            }
            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
                showingError = true
            }
        }
    }

    func handleComposerSubmit() {
        guard canSendDraft, !isBusy else { return }
        sendMessage()
    }

    func handleComposerCancel() -> Bool {
        guard isBusy else { return false }
        sendMessage()
        return true
    }

    func removeDraftAttachment(_ attachment: DraftAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        try? FileManager.default.removeItem(at: attachment.fileURL)
    }

    func toggleArtifactsEnabled() {
        conversationEntity.artifactsEnabled = !(conversationEntity.artifactsEnabled == true)
        conversationEntity.updatedAt = Date()
        try? modelContext.save()
    }
}
