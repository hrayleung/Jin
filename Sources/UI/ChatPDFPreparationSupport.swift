import Foundation

extension ChatMessagePreparationSupport {
    /// Prepends `header: filename`, trims the whole string, truncates to
    /// `maxPDFExtractedCharacters`, and wraps the result in `PreparedPDFContent`.
    ///
    /// `body` should already be trimmed by the caller before being passed in.
    static func finalizedPDFOutput(
        _ body: String,
        header: String,
        filename: String,
        additionalParts: [ContentPart] = []
    ) -> PreparedPDFContent {
        var output = "\(header): \(filename)\n\n\(body)"
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            output = "\(prefix)\n\n[Truncated]"
        }
        return PreparedPDFContent(extractedText: output, additionalParts: additionalParts)
    }
}

extension ChatMessagePreparationSupport {
    static func preparedContentForPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        requestedMode: PDFProcessingMode,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mistralClient: MistralOCRClient?,
        mineruClient: MinerUOCRClient?,
        deepSeekClient: DeepInfraDeepSeekOCRClient?,
        openRouterClient: OpenRouterOCRClient?,
        firecrawlClient: FirecrawlPDFOCRClient?,
        r2Uploader: CloudflareR2Uploader?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        let shouldSendNativePDF = profile.supportsNativePDF && requestedMode == .native
        guard !shouldSendNativePDF else {
            return PreparedPDFContent(extractedText: nil, additionalParts: [])
        }

        switch requestedMode {
        case .macOSExtract:
            return try await preparedMacOSExtractedPDF(
                attachment,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                onStatusUpdate: onStatusUpdate
            )
        case .mistralOCR:
            return try await preparedMistralOCRPDF(
                attachment,
                profile: profile,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                mistralClient: mistralClient,
                onStatusUpdate: onStatusUpdate
            )
        case .mineruOCR:
            return try await preparedMinerUOCRPDF(
                attachment,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                mineruClient: mineruClient,
                onStatusUpdate: onStatusUpdate
            )
        case .deepSeekOCR:
            return try await preparedDeepSeekOCRPDF(
                attachment,
                profile: profile,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                deepSeekClient: deepSeekClient,
                onStatusUpdate: onStatusUpdate
            )
        case .openRouterOCR:
            return try await preparedOpenRouterOCRPDF(
                attachment,
                profile: profile,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                openRouterClient: openRouterClient,
                onStatusUpdate: onStatusUpdate
            )
        case .firecrawlOCR:
            return try await preparedFirecrawlOCRPDF(
                attachment,
                profile: profile,
                totalPDFCount: totalPDFCount,
                pdfOrdinal: pdfOrdinal,
                firecrawlClient: firecrawlClient,
                r2Uploader: r2Uploader,
                onStatusUpdate: onStatusUpdate
            )
        case .native:
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }
    }
}
