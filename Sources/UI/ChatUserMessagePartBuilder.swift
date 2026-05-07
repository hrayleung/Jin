import Foundation

extension ChatMessagePreparationSupport {
    static func buildUserMessageParts(
        quoteContents: [QuoteContent],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile,
        preparedContentForPDF: (DraftAttachment, MessagePreparationProfile, PDFProcessingMode, Int, Int, MistralOCRClient?, MinerUOCRClient?, DeepInfraDeepSeekOCRClient?, OpenRouterOCRClient?, FirecrawlPDFOCRClient?, CloudflareR2Uploader?) async throws -> PreparedPDFContent
    ) async throws -> [ContentPart] {
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

        let pdfClients = try makePDFPreparationClients(
            pdfCount: pdfCount,
            requestedMode: requestedMode
        )

        var pdfOrdinal = 0
        for attachment in attachments {
            try Task.checkCancellation()

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
                pdfOrdinal += 1
                let prepared = try await preparedContentForPDF(
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
