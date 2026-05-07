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

        var output = "macOS Extract (PDF): \(attachment.filename)\n\n\(extracted)"
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            output = "\(prefix)\n\n[Truncated]"
        }

        return PreparedPDFContent(extractedText: output, additionalParts: [])
    }
}
