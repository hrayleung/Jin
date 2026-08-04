import Foundation

extension ChatMessagePreparationSupport {
    /// True when building parts needs an `await` (PDF OCR / extraction).
    /// Everything else is pure sync work and must paint on the same runloop
    /// turn as the send keypress — hopping through `Task` + `await` is what
    /// produced the blank gap between Enter and the user bubble.
    static func requiresAsyncPreparation(attachments: [DraftAttachment]) -> Bool {
        attachments.contains(where: \.isPDF)
    }

    /// Synchronous content-part build for drafts that do not need PDF work.
    /// Call only when `requiresAsyncPreparation` is false.
    static func buildUserMessagePartsSync(
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile
    ) throws -> [ContentPart] {
        precondition(
            !requiresAsyncPreparation(attachments: attachments),
            "buildUserMessagePartsSync must not be used with PDF attachments"
        )
        return try assembleUserMessageParts(
            quoteContents: quoteContents,
            messageText: messageText,
            attachments: attachments,
            remoteVideoURL: remoteVideoURL,
            profile: profile,
            preparedPDF: nil
        )
    }

    static func buildUserMessageParts(
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile,
        preparedContentForPDF: (DraftAttachment, MessagePreparationProfile, PDFProcessingMode, Int, Int, MistralOCRClient?, MinerUOCRClient?, DeepInfraDeepSeekOCRClient?, OpenRouterOCRClient?, FirecrawlPDFOCRClient?, CloudflareR2Uploader?) async throws -> PreparedPDFContent
    ) async throws -> [ContentPart] {
        let pdfCount = attachments.filter(\.isPDF).count
        let requestedMode = profile.pdfProcessingMode
        if pdfCount > 0, requestedMode == .native, !profile.supportsNativePDF {
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }

        let pdfClients = try makePDFPreparationClients(
            pdfCount: pdfCount,
            requestedMode: requestedMode
        )

        var preparedByURL: [URL: PreparedPDFContent] = [:]
        var pdfOrdinal = 0
        for attachment in attachments where attachment.isPDF {
            try Task.checkCancellation()
            pdfOrdinal += 1
            preparedByURL[attachment.fileURL] = try await preparedContentForPDF(
                attachment,
                profile,
                requestedMode,
                pdfCount,
                pdfOrdinal,
                pdfClients.mistralClient,
                pdfClients.mineruClient,
                pdfClients.deepSeekClient,
                pdfClients.openRouterClient,
                pdfClients.firecrawlClient,
                pdfClients.r2Uploader
            )
        }

        return try assembleUserMessageParts(
            quoteContents: quoteContents,
            messageText: messageText,
            attachments: attachments,
            remoteVideoURL: remoteVideoURL,
            profile: profile,
            preparedPDF: { attachment in
                preparedByURL[attachment.fileURL]
            }
        )
    }

    /// Shared assembly for sync + async paths. `preparedPDF` is only invoked
    /// for PDF attachments; the sync path never has PDFs so it stays nil.
    private static func assembleUserMessageParts(
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile,
        preparedPDF: ((DraftAttachment) -> PreparedPDFContent?)?
    ) throws -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(quoteContents.count + attachments.count + (messageText.isEmpty ? 0 : 1) + (remoteVideoURL == nil ? 0 : 1))

        if !quoteContents.isEmpty {
            parts.append(contentsOf: quoteContents.map(ContentPart.quote))
        }

        if let remoteVideoURL {
            guard profile.supportsVideoGenerationControl || profile.supportsVideoInput else {
                throw LLMError.invalidRequest(
                    message: "Remote video URL is only supported by video-capable models. (\(profile.modelName))"
                )
            }
            parts.append(
                .video(
                    VideoContent(
                        mimeType: inferredVideoMIMEType(from: remoteVideoURL),
                        data: nil,
                        url: remoteVideoURL,
                        assetDisposition: .externalReference
                    )
                )
            )
        }

        let pdfCount = attachments.filter(\.isPDF).count
        let requestedMode = profile.pdfProcessingMode
        if pdfCount > 0, requestedMode == .native, !profile.supportsNativePDF {
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }

        for attachment in attachments {
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

            if attachment.isPDF {
                guard let prepared = preparedPDF?(attachment) else {
                    throw LLMError.invalidRequest(message: "PDF preparation missing for \(attachment.filename).")
                }
                parts.append(
                    .file(
                        FileContent(
                            mimeType: attachment.mimeType,
                            filename: attachment.filename,
                            data: nil,
                            url: attachment.fileURL,
                            extractedText: prepared.extractedText
                        )
                    )
                )
                parts.append(contentsOf: prepared.additionalParts)
                continue
            }

            parts.append(
                .file(
                    FileContent(
                        mimeType: attachment.mimeType,
                        filename: attachment.filename,
                        data: nil,
                        url: attachment.fileURL,
                        extractedText: attachment.extractedText
                            ?? AttachmentImportPipeline.extractedTextIfSupported(
                                from: attachment.fileURL,
                                mimeType: attachment.mimeType
                            )
                    )
                )
            )
        }

        if !messageText.isEmpty {
            parts.append(.text(messageText))
        }

        return parts
    }
}
