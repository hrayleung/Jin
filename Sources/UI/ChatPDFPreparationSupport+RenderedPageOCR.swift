import Foundation
import PDFKit

extension ChatMessagePreparationSupport {
    /// Shared implementation for page-by-page OCR producers that render each PDF
    /// page as a JPEG and call a vision model per page.
    ///
    /// - Parameters:
    ///   - attachment: The PDF attachment to process.
    ///   - profile: Preparation profile (used for vision / image-attachment decisions).
    ///   - totalPDFCount: Total number of PDFs in the batch (for progress labelling).
    ///   - pdfOrdinal: 1-based index of this PDF in the batch.
    ///   - statusLabel: Closure that returns the per-page status string given
    ///     `(pageNumber, totalPages)` (both 1-based / max-1 adjusted).
    ///   - ocr: Async closure that performs OCR on one rendered page image,
    ///     receiving `(imageData, mimeType)` and returning raw text.
    ///   - normalize: Normalizes the raw OCR output before accumulation.
    ///   - noTextMethod: The method label used in the `noTextExtracted` error.
    ///   - header: The output header prefix (e.g. `"DeepSeek OCR (Markdown)"`).
    ///   - onStatusUpdate: Progress callback on the main actor.
    static func preparedRenderedPageOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        statusLabel: @Sendable (Int, Int) -> String,
        ocr: @Sendable (Data, String) async throws -> String,
        normalize: (String) -> String,
        noTextMethod: String,
        header: String,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        let includePageImages = profile.supportsVision
        // Render lazily, one page per OCR round-trip: rendering every page up
        // front held the whole document's JPEGs (up to 3 MB each) in memory
        // for the full multi-minute run of sequential network calls. Re-opening
        // the document per page costs a few ms against a 120 s OCR call.
        let pageCount: Int = try {
            guard let document = PDFDocument(url: attachment.fileURL) else {
                throw PDFKitImageRenderer.RenderError.failedToLoadPDF
            }
            return document.pageCount
        }()
        let totalPages = max(1, pageCount)

        var pageMarkdown: [String] = []
        pageMarkdown.reserveCapacity(pageCount)

        var imageParts: [ContentPart] = []
        if includePageImages {
            imageParts.reserveCapacity(pageCount)
        }

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            await onStatusUpdate(statusLabel(pageIndex + 1, totalPages))

            let rendered = try PDFKitImageRenderer.renderPageAsJPEG(
                from: attachment.fileURL,
                pageIndex: pageIndex
            )
            let raw = try await ocr(rendered.data, rendered.mimeType)

            let normalized = normalize(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                pageMarkdown.append(normalized)
            }

            if includePageImages {
                imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
            }
        }

        let combined = pageMarkdown
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combined.isEmpty else {
            throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: noTextMethod)
        }

        var output = combined
        if includePageImages, !imageParts.isEmpty {
            output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return finalizedPDFOutput(output, header: header, filename: attachment.filename, additionalParts: imageParts)
    }

    static func preparedDeepSeekOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        deepSeekClient: DeepInfraDeepSeekOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let deepSeekClient else { throw PDFProcessingError.deepInfraAPIKeyMissing }

        return try await preparedRenderedPageOCRPDF(
            attachment,
            profile: profile,
            totalPDFCount: totalPDFCount,
            pdfOrdinal: pdfOrdinal,
            statusLabel: { pageNumber, totalPages in
                "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (DeepSeek): \(attachment.filename) — page \(pageNumber)/\(totalPages)"
            },
            ocr: { data, mimeType in
                let prompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
                return try await deepSeekClient.ocrImage(data, mimeType: mimeType, prompt: prompt, timeoutSeconds: 120)
            },
            normalize: PDFProcessingUtilities.normalizedDeepSeekOCRMarkdown,
            noTextMethod: "DeepSeek OCR (DeepInfra)",
            header: "DeepSeek OCR (Markdown)",
            onStatusUpdate: onStatusUpdate
        )
    }

    static func preparedOpenRouterOCRPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        openRouterClient: OpenRouterOCRClient?,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> PreparedPDFContent {
        guard let openRouterClient else { throw PDFProcessingError.openRouterOCRAPIKeyMissing }

        let selectedModel = await openRouterClient.selectedModel

        return try await preparedRenderedPageOCRPDF(
            attachment,
            profile: profile,
            totalPDFCount: totalPDFCount,
            pdfOrdinal: pdfOrdinal,
            statusLabel: { pageNumber, totalPages in
                "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (OpenRouter \(selectedModel.name)): \(attachment.filename) — page \(pageNumber)/\(totalPages)"
            },
            ocr: { data, mimeType in
                try await openRouterClient.ocrImage(
                    data,
                    mimeType: mimeType,
                    prompt: OpenRouterOCRClient.Constants.defaultPrompt,
                    timeoutSeconds: 120
                )
            },
            normalize: PDFProcessingUtilities.normalizedOpenRouterOCRMarkdown,
            noTextMethod: "OpenRouter OCR",
            header: "OpenRouter OCR (\(selectedModel.name) Markdown)",
            onStatusUpdate: onStatusUpdate
        )
    }
}
