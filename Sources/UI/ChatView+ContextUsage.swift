import Foundation

struct ContextUsageSettingsSnapshot: Equatable, Sendable {
    let contextWindow: Int
    let reservedOutputTokens: Int
    let systemPrompt: String?
    let maxHistoryMessages: Int?
    let shouldTruncateMessages: Bool
    let supportsNativePDF: Bool
    let pdfProcessingMode: PDFProcessingMode
}

struct ContextUsageRefreshToken: Equatable {
    let conversationID: UUID
    let activeThreadID: UUID?
    let cachedMessagesVersion: Int
    let trimmedMessageText: String
    let trimmedRemoteVideoURLText: String
    let attachmentIDs: [UUID]
    let settings: ContextUsageSettingsSnapshot
}

private struct ContextUsageComputationInput: Sendable {
    let history: [Message]
    let draftMessageParts: [ContentPart]
    let systemPrompt: String?
    let maxHistoryMessages: Int?
    let shouldTruncateMessages: Bool
    let contextWindow: Int
    let reservedOutputTokens: Int
}

// MARK: - Context Usage

extension ChatView {

    var contextUsageRefreshToken: ContextUsageRefreshToken? {
        guard let settings = contextUsageSettingsSnapshot else { return nil }

        return ContextUsageRefreshToken(
            conversationID: conversationEntity.id,
            activeThreadID: activeThreadID,
            cachedMessagesVersion: cachedMessagesVersion,
            trimmedMessageText: trimmedMessageText,
            trimmedRemoteVideoURLText: trimmedRemoteVideoInputURLText,
            attachmentIDs: draftAttachments.map(\.id),
            settings: settings
        )
    }

    func refreshContextUsageEstimate(debounced: Bool = true) {
        contextUsageRefreshTask?.cancel()
        contextUsageRefreshTask = nil

        guard let input = makeContextUsageComputationInput() else {
            currentContextUsageEstimate = nil
            contextUsageRefreshGeneration &+= 1
            return
        }

        contextUsageRefreshGeneration &+= 1
        let generation = contextUsageRefreshGeneration

        contextUsageRefreshTask = Task {
            if debounced {
                try? await Task.sleep(for: Self.contextUsageRefreshDelay)
                guard !Task.isCancelled else { return }
            }

            let estimate = await Task.detached(priority: .utility) {
                ChatContextUsageEstimator.estimate(
                    history: input.history,
                    draftMessageParts: input.draftMessageParts,
                    systemPrompt: input.systemPrompt,
                    maxHistoryMessages: input.maxHistoryMessages,
                    shouldTruncateMessages: input.shouldTruncateMessages,
                    contextWindow: input.contextWindow,
                    reservedOutputTokens: input.reservedOutputTokens
                )
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard contextUsageRefreshGeneration == generation else { return }
                currentContextUsageEstimate = estimate
                contextUsageRefreshTask = nil
            }
        }
    }

    func clearContextUsageEstimate() {
        contextUsageRefreshTask?.cancel()
        contextUsageRefreshTask = nil
        contextUsageRefreshGeneration &+= 1
        currentContextUsageEstimate = nil
    }

    private var contextUsageSettingsSnapshot: ContextUsageSettingsSnapshot? {
        guard activeModelThread != nil || selectedModelInfo != nil else { return nil }

        let assistant = conversationEntity.assistant
        var controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: controls,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens,
            modelMaxOutputTokens: resolvedModelSettings?.maxOutputTokens
        )
        Self.sanitizeProviderSpecificForProvider(providerType, controls: &controlsToUse)

        let resolvedContextWindow = resolvedModelSettings?.contextWindow
            ?? selectedModelInfo?.contextWindow
            ?? 0

        return ContextUsageSettingsSnapshot(
            contextWindow: max(0, resolvedContextWindow),
            reservedOutputTokens: max(0, controlsToUse.maxTokens ?? 2_048),
            systemPrompt: resolvedSystemPrompt(
                conversationSystemPrompt: conversationEntity.systemPrompt,
                assistant: assistant
            ),
            maxHistoryMessages: assistant?.maxHistoryMessages,
            shouldTruncateMessages: assistant?.truncateMessages ?? false,
            supportsNativePDF: supportsNativePDF,
            pdfProcessingMode: resolvedPDFProcessingMode
        )
    }

    private func makeContextUsageComputationInput() -> ContextUsageComputationInput? {
        guard let settings = contextUsageSettingsSnapshot else { return nil }

        return ContextUsageComputationInput(
            history: cachedActiveThreadHistory,
            draftMessageParts: contextUsageDraftMessageParts(settings: settings),
            systemPrompt: settings.systemPrompt,
            maxHistoryMessages: settings.maxHistoryMessages,
            shouldTruncateMessages: settings.shouldTruncateMessages,
            contextWindow: settings.contextWindow,
            reservedOutputTokens: settings.reservedOutputTokens
        )
    }

    private func contextUsageDraftMessageParts(settings: ContextUsageSettingsSnapshot) -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(draftAttachments.count + (trimmedMessageText.isEmpty ? 0 : 1) + 1)

        if let remoteVideoURL = try? resolvedRemoteVideoInputURL(from: trimmedRemoteVideoInputURLText) {
            parts.append(
                .video(
                    VideoContent(
                        mimeType: ChatMessagePreparationSupport.inferredVideoMIMEType(from: remoteVideoURL),
                        data: nil,
                        url: remoteVideoURL,
                        assetDisposition: .externalReference
                    )
                )
            )
        }

        for attachment in draftAttachments {
            if attachment.isImage {
                parts.append(.image(ImageContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isVideo {
                parts.append(.video(VideoContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isAudio {
                parts.append(.audio(AudioContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            let extractedText: String?
            if attachment.isPDF && settings.supportsNativePDF && settings.pdfProcessingMode == .native {
                extractedText = nil
            } else {
                extractedText = attachment.extractedText
            }

            parts.append(
                .file(
                    FileContent(
                        mimeType: attachment.mimeType,
                        filename: attachment.filename,
                        data: nil,
                        url: attachment.fileURL,
                        extractedText: extractedText
                    )
                )
            )
        }

        if !trimmedMessageText.isEmpty {
            parts.append(.text(trimmedMessageText))
        }

        return parts
    }
}
