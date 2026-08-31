import Foundation
import PDFKit

extension ChatMessagePreparationSupport {
    /// Rasterize each PDF page to JPEG and attach the images. No OCR API.
    /// Used when the chat model has vision but cannot accept `application/pdf`.
    static func preparedPagesAsImagesPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard profile.supportsVision else {
            throw PDFProcessingError.pagesAsImagesNotSupported(modelName: profile.modelName)
        }

        let pageCount: Int = try {
            guard let document = PDFDocument(url: attachment.fileURL) else {
                throw PDFKitImageRenderer.RenderError.failedToLoadPDF
            }
            return document.pageCount
        }()
        let totalPages = max(1, pageCount)
        let pageLimit: Int = {
            if let cap = profile.maxVisionImagesPerRequest, cap > 0 {
                return min(pageCount, cap)
            }
            return pageCount
        }()

        var imageParts: [ContentPart] = []
        imageParts.reserveCapacity(pageLimit)

        for pageIndex in 0..<pageLimit {
            try Task.checkCancellation()
            await onStatusUpdate(
                "Render PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (pages): \(attachment.filename) — page \(pageIndex + 1)/\(totalPages)"
            )

            let rendered = try PDFKitImageRenderer.renderPageAsJPEG(
                from: attachment.fileURL,
                pageIndex: pageIndex
            )
            imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
        }

        guard !imageParts.isEmpty else {
            throw PDFProcessingError.noTextExtracted(
                filename: attachment.filename,
                method: "Pages as images"
            )
        }

        let attachedNote: String
        if pageLimit < pageCount {
            attachedNote = "[Note: Attached the first \(pageLimit) of \(pageCount) page images (provider limit).]"
        } else {
            attachedNote = "[Note: Attached \(imageParts.count) page image(s).]"
        }
        let body = "The PDF pages are attached as images for visual reading. Treat the images as the document's contents.\n\n\(attachedNote)"

        return finalizedPDFOutput(
            body,
            header: "Pages as images",
            filename: attachment.filename,
            additionalParts: imageParts
        )
    }
}
