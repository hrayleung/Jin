import Foundation

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
        let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
        let totalPages = max(1, renderedPages.count)

        var pageMarkdown: [String] = []
        pageMarkdown.reserveCapacity(renderedPages.count)

        var imageParts: [ContentPart] = []
        var totalAttachedBytes = 0

        for rendered in renderedPages {
            try Task.checkCancellation()

            await onStatusUpdate(statusLabel(rendered.pageIndex + 1, totalPages))

            let raw = try await ocr(rendered.data, rendered.mimeType)

            let normalized = normalize(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                pageMarkdown.append(normalized)
            }

            if includePageImages,
               imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                let nextTotal = totalAttachedBytes + rendered.data.count
                if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                    totalAttachedBytes = nextTotal
                    imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                }
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
            let omitted = max(0, renderedPages.count - imageParts.count)
            output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
            if omitted > 0 {
                output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
            }
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
