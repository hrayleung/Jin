import Foundation

extension ChatMessagePreparationSupport {
    static func preparedMinerUOCRPDF(
        _ attachment: DraftAttachment,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mineruClient: MinerUOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let mineruClient else { throw PDFProcessingError.mineruAPITokenMissing }

        await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (MinerU): \(attachment.filename)")

        guard let data = try? Data(contentsOf: attachment.fileURL) else {
            throw PDFProcessingError.fileReadFailed(filename: attachment.filename)
        }

        let storedLanguage = UserDefaults.standard
            .string(forKey: AppPreferenceKeys.pluginMineruOCRLanguage)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let language = storedLanguage.flatMap { $0.isEmpty ? nil : $0 }
            ?? MinerUOCRClient.Constants.defaultLanguage
        let markdown = try await mineruClient.ocrPDF(
            data,
            filename: attachment.filename,
            language: language,
            timeoutSeconds: 180
        )

        let combined = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "MinerU OCR")
        }

        return finalizedPDFOutput(combined, header: "MinerU OCR (Markdown)", filename: attachment.filename)
    }

    static func preparedFirecrawlOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        firecrawlClient: FirecrawlPDFOCRClient?,
        r2Uploader: CloudflareR2Uploader?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let firecrawlClient else { throw PDFProcessingError.firecrawlAPIKeyMissing }
        guard let r2Uploader else {
            throw LLMError.invalidRequest(message: "Firecrawl OCR requires the Cloudflare R2 uploader.")
        }
        guard await r2Uploader.isPluginEnabled() else {
            throw LLMError.invalidRequest(
                message: "Firecrawl OCR requires Cloudflare R2 Upload to be enabled in Settings → Plugins."
            )
        }

        await onStatusUpdate("Uploading PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Cloudflare R2): \(attachment.filename)")

        let hostedURL = try await r2Uploader.uploadPDF(
            FileContent(
                mimeType: attachment.mimeType,
                filename: attachment.filename,
                data: nil,
                url: attachment.fileURL
            )
        )
        defer {
            Task {
                try? await r2Uploader.deleteUploadedObject(at: hostedURL)
            }
        }

        let parserMode = profile.firecrawlPDFParserMode
        await onStatusUpdate("OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Firecrawl \(parserMode.displayName)): \(attachment.filename)")

        let markdown = try await firecrawlClient.scrapePDF(
            at: hostedURL,
            mode: parserMode,
            timeoutSeconds: 180
        )
        let combined = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Firecrawl OCR")
        }

        return finalizedPDFOutput(combined, header: "Firecrawl OCR (\(parserMode.displayName) Markdown)", filename: attachment.filename)
    }
}
