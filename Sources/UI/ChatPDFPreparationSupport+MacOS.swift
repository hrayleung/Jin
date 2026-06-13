import Foundation

extension ChatMessagePreparationSupport {
    static func preparedMacOSExtractedPDF(
        _ attachment: DraftAttachment,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        await onStatusUpdate("Extracting PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (macOS): \(attachment.filename)")

        guard let extracted = PDFKitTextExtractor.extractText(
            from: attachment.fileURL,
            maxCharacters: AttachmentConstants.maxPDFExtractedCharacters
        ) else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "macOS Extract")
        }

        return finalizedPDFOutput(extracted, header: "macOS Extract (PDF)", filename: attachment.filename)
    }
}
