import Foundation

// MARK: - Context Usage

extension ChatView {

    var currentContextUsageEstimate: ChatContextUsageEstimate? {
        guard activeModelThread != nil || selectedModelInfo != nil else { return nil }

        let assistant = conversationEntity.assistant
        var controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: controls,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens,
            modelMaxOutputTokens: resolvedModelSettings?.maxOutputTokens
        )
        let resolvedContextWindow = resolvedModelSettings?.contextWindow
            ?? selectedModelInfo?.contextWindow
            ?? 0
        let contextWindow = max(0, resolvedContextWindow)
        Self.sanitizeProviderSpecificForProvider(providerType, controls: &controlsToUse)

        return ChatContextUsageEstimator.estimate(
            history: cachedActiveThreadHistory,
            draftMessageParts: contextUsageDraftMessageParts,
            systemPrompt: resolvedSystemPrompt(
                conversationSystemPrompt: conversationEntity.systemPrompt,
                assistant: assistant
            ),
            maxHistoryMessages: assistant?.maxHistoryMessages,
            shouldTruncateMessages: assistant?.truncateMessages ?? false,
            contextWindow: contextWindow,
            reservedOutputTokens: max(0, controlsToUse.maxTokens ?? 2_048)
        )
    }

    private var contextUsageDraftMessageParts: [ContentPart] {
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
            if attachment.isPDF && supportsNativePDF && resolvedPDFProcessingMode == .native {
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
