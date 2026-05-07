import Foundation

// MARK: - Message Preparation

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
            let hasTextualPrompt = ChatMessagePreparationSupport.hasTextualPrompt(
                messageText: messageText,
                quoteContents: quoteContents
            )
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
}
